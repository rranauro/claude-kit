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
# it no-ops anyway if the Gemfile doesn't carry both tools.
# Kill switch: export SKIP_RAILS_GATES=1.

set -u

# --- Manual kill switch -------------------------------------------------------
[[ -n "${SKIP_RAILS_GATES:-}" ]] && exit 0

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

# --- Only act on a Rails project that actually has these tools ----------------
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$ROOT/Gemfile" ] || exit 0
grep -q 'rubocop' "$ROOT/Gemfile" || exit 0
grep -q 'brakeman' "$ROOT/Gemfile" || exit 0

cd "$ROOT" || exit 0

# Staged Ruby files — the commit is about to capture exactly these.
# Built with a read loop, not `mapfile`: that's bash 4+, and macOS ships 3.2.
RB_LIST=$(git diff --cached --name-only --diff-filter=ACM -- '*.rb' 2>/dev/null)
RB_FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && RB_FILES+=("$f")
done <<EOF
$RB_LIST
EOF

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

# --- RuboCop, scoped to what's being committed --------------------------------
# Guard the count before expanding: "${arr[@]}" on an empty array trips `set -u`
# on bash 3.2.
if [ "${#RB_FILES[@]}" -gt 0 ]; then
  if ! RUBOCOP_OUT=$(bundle exec rubocop --force-exclusion "${RB_FILES[@]}" 2>&1); then
    FAILURES+="RuboCop failed on the staged Ruby files:

$(trim "$RUBOCOP_OUT")

Run \`bundle exec rubocop -A\` on those files for the autocorrectable offenses,
then decide the rest by hand — do not blanket-disable cops to get past this gate.

"
  fi
fi

# --- Brakeman, whole app (it has no meaningful per-file mode) ------------------
# Only worth running when the staged set touches app code.
if printf '%s\n' "$RB_LIST" | grep -q '^app/'; then
  if ! BRAKEMAN_OUT=$(bundle exec brakeman -q --no-pager --exit-on-warn 2>&1); then
    FAILURES+="Brakeman reported security warnings:

$(trim "$BRAKEMAN_OUT")

Triage each one — fix the real findings; for a false positive, say why in the
commit body rather than silently ignoring it.

"
  fi
fi

[ -n "$FAILURES" ] || exit 0

# Exit 2 blocks the tool call and feeds stderr back to Claude.
printf '%s' "Commit blocked by the rails-quality-gates hook.

${FAILURES}Fix the above and retry the commit. If this gate is wrong for this
change, the user can re-run with SKIP_RAILS_GATES=1 — ask before doing that
rather than deciding it yourself.
" >&2
exit 2
