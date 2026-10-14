#!/usr/bin/env bash
set -uo pipefail

# What the commit gate owns, asserted against throwaway repositories with a
# stub `bundle` on PATH.
#
# The hook's failure mode is silence: a gate that never finds the app exits 0
# exactly as a gate that passed does, so nothing downstream can tell the two
# apart. These cases pin which directory each tool runs in, and the one line a
# person sees when the gate could not run.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/plugins/kit/hooks/rails-quality-gates.sh"

passed=0
failed=0
current=""

# --- assertions ---------------------------------------------------------

ok()  { echo "  ok   $current — $1"; passed=$((passed + 1)); }
bad() { echo "  FAIL $current — $1" >&2; failed=$((failed + 1)); }

assert_has() { # haystack needle label
  case "$1" in
    *"$2"*) ok "$3" ;;
    *)      bad "$3"; printf '       expected to find: %s\n' "$2" >&2
            printf '       in:\n%s\n' "$1" | sed 's/^/         /' >&2 ;;
  esac
}

assert_lacks() { # haystack needle label
  case "$1" in
    *"$2"*) bad "$3"; printf '       expected NOT to find: %s\n' "$2" >&2
            printf '       in:\n%s\n' "$1" | sed 's/^/         /' >&2 ;;
    *)      ok "$3" ;;
  esac
}

assert_eq() { # actual expected label
  if [ "$1" = "$2" ]; then ok "$3"
  else bad "$3"; printf '       expected: %s\n       actual:   %s\n' "$2" "$1" >&2; fi
}

# --- sandbox ------------------------------------------------------------

new_sandbox() {
  current="$1"
  echo "==> $current"
  # -P: the hook cds to git's toplevel, which is /private/var/... on macOS
  # while mktemp hands back /var/..., and the stub logs the directory it ran in.
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  REPO="$SANDBOX/repo"
  LOG="$SANDBOX/bundle.log"
  : > "$LOG"

  mkdir -p "$SANDBOX/bin"
  # Records where each tool ran and on what, and fails the tool named in
  # STUB_FAIL so a case can provoke a block.
  cat > "$SANDBOX/bin/bundle" <<'SH'
#!/usr/bin/env bash
tool="$2"
echo "$tool @ $PWD : ${*:3}" >> "$STUB_LOG"
case " ${STUB_FAIL:-} " in
  *" $tool "*) echo "$tool offense in $PWD"; exit 1 ;;
esac
exit 0
SH
  chmod +x "$SANDBOX/bin/bundle"

  git init -q "$REPO"
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name "Test"
  echo hello > "$REPO/README.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm initial
}

end_sandbox() {
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
}

gated_gemfile() { # dir
  mkdir -p "$REPO/$1"
  printf "source 'https://rubygems.org'\ngem 'rails'\ngem 'rubocop'\ngem 'brakeman'\n" > "$REPO/$1/Gemfile"
}

stage() { # path...
  local f
  for f in "$@"; do
    mkdir -p "$(dirname "$REPO/$f")"
    echo "# frozen_string_literal: true" > "$REPO/$f"
    git -C "$REPO" add "$f"
  done
}

# Runs the hook as Claude Code would on a Bash call. Sets STATUS, OUT, ERR.
hook() { # command
  local input
  input="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1")"
  OUT="$(cd "$REPO" && printf '%s' "$input" \
    | PATH="$SANDBOX/bin:$PATH" STUB_LOG="$LOG" bash "$HOOK" 2>"$SANDBOX/err")"
  STATUS=$?
  ERR="$(cat "$SANDBOX/err")"
}

# The `systemMessage` the hook printed, or empty.
notice() {
  printf '%s' "$OUT" | python3 -c 'import json,sys
s = sys.stdin.read().strip()
print(json.loads(s).get("systemMessage", "") if s else "")'
}

# ========================================================================
# AC · A commit staging Ruby in a nested Rails app gets the same RuboCop and
#      Brakeman checks a root-level app gets.
# ========================================================================

new_sandbox "a nested app is gated from its own directory"
gated_gemfile apps/web
stage apps/web/app/models/user.rb
hook "git commit -m 'Add user'"
assert_eq "$STATUS" 0 "a clean commit passes"
assert_has "$(cat "$LOG")" "rubocop @ $REPO/apps/web : --force-exclusion app/models/user.rb" \
  "RuboCop runs inside the app, on paths relative to it"
assert_has "$(cat "$LOG")" "brakeman @ $REPO/apps/web" \
  "Brakeman runs inside the app when its app/ is touched"
end_sandbox

new_sandbox "a nested app's offenses block the commit and name the app"
gated_gemfile apps/web
stage apps/web/app/models/user.rb
STUB_FAIL="rubocop brakeman" hook "git commit -m 'Add user'"
assert_eq "$STATUS" 2 "the commit is blocked"
assert_has "$ERR" "rubocop offense in $REPO/apps/web" "the RuboCop output reaches Claude"
assert_has "$ERR" "brakeman offense in $REPO/apps/web" "the Brakeman output reaches Claude"
assert_has "$ERR" "apps/web" "the block names which app failed"
end_sandbox

new_sandbox "two nested apps are each gated in their own directory"
gated_gemfile apps/web
gated_gemfile apps/admin
stage apps/web/lib/a.rb apps/admin/app/b.rb
hook "git commit -m 'Both'"
assert_has "$(cat "$LOG")" "rubocop @ $REPO/apps/web : --force-exclusion lib/a.rb" "the web app's file is linted from web"
assert_has "$(cat "$LOG")" "rubocop @ $REPO/apps/admin : --force-exclusion app/b.rb" "the admin app's file is linted from admin"
assert_has "$(cat "$LOG")" "brakeman @ $REPO/apps/admin" "Brakeman runs for the app whose app/ is touched"
assert_lacks "$(cat "$LOG")" "brakeman @ $REPO/apps/web" "and not for the one whose app/ is not"
end_sandbox

# ========================================================================
# AC · A commit to a single-app repository is gated exactly as it is today.
# ========================================================================

new_sandbox "a root app is gated from the root, as before"
gated_gemfile .
stage app/models/user.rb lib/tasks/x.rb
hook "git commit -m 'Root'"
assert_eq "$STATUS" 0 "a clean commit passes"
assert_has "$(cat "$LOG")" "rubocop @ $REPO : --force-exclusion app/models/user.rb lib/tasks/x.rb" \
  "RuboCop runs at the root on the staged paths"
assert_has "$(cat "$LOG")" "brakeman @ $REPO" "Brakeman runs when app/ is touched"
assert_eq "$OUT" "" "and nothing new is printed"
end_sandbox

new_sandbox "a root app's block message reads as it did"
gated_gemfile .
stage app/models/user.rb
STUB_FAIL="rubocop" hook "git commit -m 'Root'"
assert_eq "$STATUS" 2 "the commit is blocked"
assert_has "$ERR" "RuboCop failed on the staged Ruby files:" "the heading is unchanged"
end_sandbox

new_sandbox "an engine's own Gemfile does not take its files out of the root gate"
gated_gemfile .
mkdir -p "$REPO/engines/billing"
printf "source 'https://rubygems.org'\ngemspec\n" > "$REPO/engines/billing/Gemfile"
stage engines/billing/lib/billing.rb
hook "git commit -m 'Engine'"
assert_has "$(cat "$LOG")" "rubocop @ $REPO : --force-exclusion engines/billing/lib/billing.rb" \
  "the root still lints the engine's file"
assert_lacks "$(cat "$LOG")" "brakeman" "and Brakeman stays keyed to the root's app/"
end_sandbox

new_sandbox "the hook's own remediation commit is let through"
gated_gemfile .
stage app/models/user.rb
STUB_FAIL="rubocop" hook "git commit -m 'Fix rubocop offenses'"
assert_eq "$STATUS" 0 "it is not gated"
assert_eq "$(cat "$LOG")" "" "and runs nothing"
end_sandbox

# ========================================================================
# AC · Where there is a Rails app the hook could not gate, or the gates are
#      switched off, the person sees one line. Otherwise nothing new.
# ========================================================================

new_sandbox "a Rails app without the tools gets one line"
mkdir -p "$REPO/apps/web"
printf "source 'https://rubygems.org'\ngem \"rails\"\n" > "$REPO/apps/web/Gemfile"
stage apps/web/app/models/user.rb
hook "git commit -m 'Ungated'"
assert_eq "$STATUS" 0 "the commit goes through"
assert_has "$(notice)" "apps/web" "the line names the app"
assert_has "$(notice)" "rubocop and brakeman" "and says why it could not be gated"
assert_eq "$(notice | wc -l | tr -d ' ')" "1" "it is one line"
assert_eq "$(cat "$LOG")" "" "nothing ran"
end_sandbox

new_sandbox "a parenthesized rails declaration counts as a Rails app"
mkdir -p "$REPO/apps/web"
printf "gem('rails', '~> 7.1')\n" > "$REPO/apps/web/Gemfile"
stage apps/web/app/models/user.rb
hook "git commit -m 'Ungated'"
assert_has "$(notice)" "apps/web" "the skip line still names the app"
end_sandbox

new_sandbox "the kill switch says it is on"
gated_gemfile apps/web
stage apps/web/app/models/user.rb
SKIP_RAILS_GATES=1 hook "git commit -m 'Skip'"
assert_eq "$STATUS" 0 "the commit goes through"
assert_has "$(notice)" "SKIP_RAILS_GATES" "the line names the switch"
assert_eq "$(cat "$LOG")" "" "nothing ran"
end_sandbox

new_sandbox "the kill switch is silent where there was nothing to gate"
gated_gemfile .
echo docs > "$REPO/NOTES.md"; git -C "$REPO" add NOTES.md
SKIP_RAILS_GATES=1 hook "git commit -m 'Docs'"
assert_eq "$OUT" "" "a commit with no Ruby staged prints nothing"
end_sandbox

new_sandbox "a commit with no Ruby staged prints nothing"
gated_gemfile .
echo docs > "$REPO/NOTES.md"; git -C "$REPO" add NOTES.md
hook "git commit -m 'Docs'"
assert_eq "$STATUS" 0 "it passes"
assert_eq "$OUT$ERR" "" "and prints nothing"
end_sandbox

new_sandbox "Ruby outside any Rails app prints nothing"
mkdir -p "$REPO/tools"
printf "source 'https://rubygems.org'\ngem 'rubocop-rails'\n" > "$REPO/tools/Gemfile"
stage tools/script.rb scripts/loose.rb
hook "git commit -m 'Scripts'"
assert_eq "$STATUS" 0 "it passes"
assert_eq "$OUT$ERR" "" "and prints nothing"
end_sandbox

new_sandbox "a gated app blocked alongside an ungated one carries both"
gated_gemfile apps/web
mkdir -p "$REPO/apps/admin"
printf "gem 'rails'\n" > "$REPO/apps/admin/Gemfile"
stage apps/web/lib/a.rb apps/admin/app/b.rb
STUB_FAIL="rubocop" hook "git commit -m 'Mixed'"
assert_eq "$STATUS" 2 "the commit is blocked"
assert_has "$ERR" "apps/admin" "the skip line rides along on the block"
end_sandbox

new_sandbox "a command that is not a commit is ignored"
gated_gemfile .
stage app/models/user.rb
SKIP_RAILS_GATES=1 hook "git status"
assert_eq "$STATUS$OUT$ERR" "0" "nothing happens"
end_sandbox

# --- summary ------------------------------------------------------------

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
