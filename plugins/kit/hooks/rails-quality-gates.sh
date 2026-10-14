#!/usr/bin/env bash
# PreToolUse hook: before a `git commit` runs in a Claude Code Bash call, hold it
# to the Rails quality gates — RuboCop and Brakeman — on the staged Ruby files.
# Blocks the commit (exit 2) with the tool output on stderr, which Claude reads
# and fixes before retrying.
#
# The hook ENFORCES; the /kit:commit command REMEDIATES. Nothing here tries to
# autofix: deciding whether a Brakeman finding is a real XSS or a false positive
# is judgment, and a shell hook has none. It only answers pass/fail.
#
# Tests are deliberately NOT run here. Choosing which specs cover a change is the
# same judgment call, and a full suite would blow the hook timeout.
#
# Register it in a project's .claude/settings.json rather than the global one, so
# it fires only for Rails repos. Non-Rails projects simply never enable it, and
# it no-ops anyway on Ruby no Gemfile carrying both tools sits above.
# Kill switch: export SKIP_RAILS_GATES=1.
#
# A gate that cannot run exits 0 exactly as a gate that passed does, so where a
# Rails app was staged and nothing gated it, the person is told in one line.
# Everywhere else the hook stays silent: a line on every docs commit is a line
# nobody reads.

set -u

INPUT=$(cat)

# Extract the Bash command, but only for `git commit` calls. Also filters out the
# hook's own remediation commits: without this, the "Fix rubocop offenses" commit
# Claude makes in response to a block would re-enter the gate and loop.
CMD=$(INPUT="$INPUT" python3 - <<'PY'
import json, os, re, sys
d = json.loads(os.environ.get("INPUT") or "{}")
if d.get("tool_name") != "Bash":
    sys.exit(0)
cmd = (d.get("tool_input") or {}).get("command", "") or ""
if not re.search(r'\bgit\s+commit\b', cmd):
    sys.exit(0)
# Remediation commits this hook provoked — let them through.
if re.search(r'Fix (rubocop offenses|brakeman security warnings)', cmd):
    sys.exit(0)
print(cmd)
PY
)

[ -n "$CMD" ] || exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$ROOT" || exit 0

# Staged Ruby files — the commit is about to capture exactly these.
RB_LIST=$(git diff --cached --name-only --diff-filter=ACM -- '*.rb' 2>/dev/null)
[ -n "$RB_LIST" ] || exit 0

# --- Which app gates each file -------------------------------------------------
# The nearest directory above a file whose Gemfile carries both tools, the same
# way Bundler finds an app by walking up to its Gemfile. Nearest *gateable*, not
# nearest: an engine's own `gemspec` Gemfile inside a root app would otherwise
# take the engine's files out of the gate the root has always held them to.
carries_gates() {
  [ -f "$1/Gemfile" ] && grep -q 'rubocop' "$1/Gemfile" && grep -q 'brakeman' "$1/Gemfile"
}
names_rails() {
  [ -f "$1/Gemfile" ] && grep -Eq "^[[:space:]]*gem[[:space:]]+['\"](rails|railties)['\"]" "$1/Gemfile"
}

# One "gated|ungated <TAB> app-dir <TAB> file" line per file in a Rails app or
# under a gateable Gemfile; Ruby in neither is not this hook's business.
# A read loop, not `mapfile` or an associative array: macOS ships bash 3.2.
RESOLVED=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  dir=$(dirname "$f")
  rails=""
  kind=""
  while :; do
    if carries_gates "$dir"; then kind=gated; break; fi
    [ -z "$rails" ] && names_rails "$dir" && rails="$dir"
    [ "$dir" = "." ] && break
    dir=$(dirname "$dir")
  done
  if [ -n "$kind" ]; then
    RESOLVED+="gated	$dir	$f
"
  elif [ -n "$rails" ]; then
    RESOLVED+="ungated	$rails	$f
"
  fi
done <<EOF
$RB_LIST
EOF

[ -n "$RESOLVED" ] || exit 0

apps_of() { # kind
  printf '%s' "$RESOLVED" | awk -F'\t' -v k="$1" '$1 == k { print $2 }' | sort -u
}
label() { # app-dir
  if [ "$1" = "." ]; then printf 'the app at the repository root'; else printf '%s' "$1"; fi
}

NOTICE=""
if [ -n "${SKIP_RAILS_GATES:-}" ]; then
  NOTICE="Rails quality gates skipped: SKIP_RAILS_GATES is set, so RuboCop and Brakeman did not run on this commit."
else
  UNGATED=""
  while IFS= read -r app; do
    [ -n "$app" ] && UNGATED+="${UNGATED:+, }$(label "$app")"
  done <<EOF
$(apps_of ungated)
EOF
  [ -n "$UNGATED" ] && NOTICE="Rails quality gates skipped for $UNGATED: no Gemfile at or above it carries both rubocop and brakeman."
fi

# A systemMessage is what reaches the person; plain stdout on exit 0 only
# reaches the transcript view.
say_notice() {
  NOTICE="$NOTICE" python3 -c 'import json, os; print(json.dumps({"systemMessage": os.environ["NOTICE"]}))'
}

[ -n "${SKIP_RAILS_GATES:-}" ] && { say_notice; exit 0; }

FAILURES=""

# Tool output goes straight into Claude's context on a block. RuboCop in
# particular prepends a long "new cops are available" banner on any repo whose
# .rubocop.yml is behind the gem. Keep the tail — the offenses are at the end.
trim() {
  local text="$1" limit=60 total
  total=$(printf '%s\n' "$text" | wc -l | tr -d ' ')
  if [ "$total" -gt "$limit" ]; then
    printf '[…%s earlier lines trimmed by the hook…]\n%s' \
      "$((total - limit))" "$(printf '%s\n' "$text" | tail -n "$limit")"
  else
    printf '%s' "$text"
  fi
}

# --- Each app, from its own directory -----------------------------------------
# A nested app's bundle, .rubocop.yml and Brakeman config all live in its own
# directory, so the tools run there on paths relative to it. At the root that is
# the command this hook has always run, and its block message reads as it did.
while IFS= read -r app; do
  [ -n "$app" ] || continue
  where=""
  [ "$app" = "." ] || where=" in $app"

  RB_FILES=()
  while IFS='	' read -r kind dir f; do
    [ "$kind" = gated ] && [ "$dir" = "$app" ] && RB_FILES+=("${f#"$app"/}")
  done <<EOF
$RESOLVED
EOF

  # --- RuboCop, scoped to what's being committed ------------------------------
  # Guard the count before expanding: "${arr[@]}" on an empty array trips
  # `set -u` on bash 3.2.
  if [ "${#RB_FILES[@]}" -gt 0 ]; then
    if ! RUBOCOP_OUT=$(cd "$app" && bundle exec rubocop --force-exclusion "${RB_FILES[@]}" 2>&1); then
      FAILURES+="RuboCop failed on the staged Ruby files${where}:

$(trim "$RUBOCOP_OUT")

Run \`bundle exec rubocop -A\` on those files${where:+ from $app} for the autocorrectable offenses,
then decide the rest by hand — do not blanket-disable cops to get past this gate.

"
    fi
  fi

  # --- Brakeman, whole app (it has no meaningful per-file mode) ---------------
  # Only worth running when the staged set touches this app's code.
  if printf '%s\n' "${RB_FILES[@]}" | grep -q '^app/'; then
    if ! BRAKEMAN_OUT=$(cd "$app" && bundle exec brakeman -q --no-pager --exit-on-warn 2>&1); then
      FAILURES+="Brakeman reported security warnings${where}:

$(trim "$BRAKEMAN_OUT")

Triage each one — fix the real findings; for a false positive, say why in the
commit body rather than silently ignoring it.

"
    fi
  fi
done <<EOF
$(apps_of gated)
EOF

if [ -z "$FAILURES" ]; then
  [ -z "$NOTICE" ] || say_notice
  exit 0
fi

# Exit 2 blocks the tool call and feeds stderr back to Claude; a systemMessage
# printed alongside would be dropped, so a skip line rides on stderr instead.
printf '%s' "Commit blocked by the rails-quality-gates hook.

${FAILURES}${NOTICE:+$NOTICE

}Fix the above and retry the commit. If this gate is wrong for this
change, the user can re-run with SKIP_RAILS_GATES=1 — ask before doing that
rather than deciding it yourself.
" >&2
exit 2
