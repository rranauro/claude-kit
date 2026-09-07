#!/usr/bin/env bash
set -uo pipefail

# Every acceptance criterion that lives in the runner is asserted here against a
# throwaway repository, with `claude` and `gh` stubbed on PATH so both the
# /kit:list reply and the PR listing are fixtures the test holds still.
#
# Each is the point rather than a convenience. One defect was that a reply
# meaning *take nothing* was read as naming a ticket, so the test that separates
# the two feeds in a reply whose prose says one thing and whose offer block says
# the other. The other was that a PR was resolved from its branch name, so the
# test that separates the two feeds in a PR whose branch carries no issue number
# and whose closing link does.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/plugins/kit/scripts/ship-startable.sh"
ORIG_PATH="$PATH"
ORIG_HOME="$HOME"

passed=0
failed=0
current=""

# --- assertions ---------------------------------------------------------

ok()   { echo "  ok   $current — $1"; passed=$((passed + 1)); }
bad()  { echo "  FAIL $current — $1" >&2; failed=$((failed + 1)); }

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

# --- sandbox ------------------------------------------------------------

new_sandbox() {
  current="$1"
  echo "==> $current"
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  MAIN="$SANDBOX/main"

  git init -q "$MAIN"
  git -C "$MAIN" symbolic-ref HEAD refs/heads/main
  git -C "$MAIN" config user.email test@example.com
  git -C "$MAIN" config user.name "Test"
  echo hello > "$MAIN/README.md"
  git -C "$MAIN" add -A
  git -C "$MAIN" commit -qm initial

  REPLY_FILE="$SANDBOX/list-reply.txt"
  mkdir -p "$SANDBOX/bin"

  # Answers `/kit:list` from the fixture and anything else with a token line, so
  # a ship-ticket call is never mistaken for the under-floor return that means
  # the plugin failed to resolve.
  cat > "$SANDBOX/bin/claude" <<'CLAUDE'
#!/usr/bin/env bash
prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) prompt="$2"; shift 2 ;;
    *)  shift ;;
  esac
done
case "$prompt" in
  */kit:list*) cat "$REPLY_FILE" ;;
  # A ship-ticket call that returns instantly is under the script's own
  # floor and is an anomaly before any PR is looked up, so a test that
  # asserts on the lookup has to outlast the floor.
  *)           sleep "${SHIP_STUB_DELAY:-0}"; echo "ship-ticket stub ran" ;;
esac
CLAUDE
  chmod +x "$SANDBOX/bin/claude"

  # Answers the PR listing from a fixture and every other lookup with an empty,
  # well-formed result — enough for the script's preflight, and enough that a
  # test says nothing about GitHub state it did not set.
  cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$*" in
  *"pr list --state all"*) cat "$PR_LIST_FIXTURE" ;;
  *--json*)                echo '[]' ;;
  *)                       : ;;
esac
GH
  chmod +x "$SANDBOX/bin/gh"

  PR_LIST_FIXTURE="$SANDBOX/pr-list.json"
  echo '[]' > "$PR_LIST_FIXTURE"

  SHIP_STUB_DELAY=0
  export REPLY_FILE PR_LIST_FIXTURE SHIP_STUB_DELAY
  export PATH="$SANDBOX/bin:$ORIG_PATH"
  # The script writes its log under $HOME; keep that inside the sandbox.
  export HOME="$SANDBOX"
}

end_sandbox() {
  PATH="$ORIG_PATH"
  HOME="$ORIG_HOME"
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
}

reply() { cat > "$REPLY_FILE"; }
pr_list() { cat > "$PR_LIST_FIXTURE"; }

run() { # args... -> runs the script against $MAIN with stdin closed
  "$SCRIPT" "$@" --repo "$MAIN" --max 1 --poll-seconds 1 </dev/null 2>&1
}

# ========================================================================
# AC · The block's line for the label is the only thing the run reads.
# ========================================================================

new_sandbox "a block line with numbers offers the lowest"
reply <<'R'
ready-for-agent + bug
  #52  Reconcile the webhook retry window
  #58  Stop the importer swallowing a 409

<!-- kit-startable: begin -->
bug: 52,58
<!-- kit-startable: end -->
R
out="$(run bug)"
assert_has "$out" "taking #52" "the lowest number on the line is taken"
end_sandbox

new_sandbox "prose naming an excluded ticket offers nothing"
reply <<'R'
#52 already has open PR #61 ("Closes #52") — condition 5 fails, so it is not
startable.

ready-for-agent + bug
  nothing startable (#52 already has open PR #61)

<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
out="$(run bug)"
assert_lacks "$out" "taking #" "a ticket named only to exclude it is not taken"
assert_has "$out" "done: nothing startable" "an empty line is the quiet nothing-startable path"
end_sandbox

new_sandbox "a reply with no block is unreadable"
reply <<'R'
ready-for-agent + bug
  #52  Reconcile the webhook retry window
R
out="$(run bug)"
assert_lacks "$out" "taking #" "nothing is taken from a reply with no block"
assert_has "$out" "unreadable" "the run stops naming the reply as unreadable"
end_sandbox

new_sandbox "a mistyped label is unreadable, not a drained backlog"
reply <<'R'
ready-for-agent + bg
  no such label — did you mean `bug`?

<!-- kit-startable: begin -->
<!-- kit-startable: end -->
R
out="$(run bg)"
assert_lacks "$out" "taking #" "nothing is taken when the label has no line"
assert_has "$out" "unreadable" "a missing line stops the run"
assert_lacks "$out" "done: nothing startable" "a missing line does not read as a drained backlog"
end_sandbox

new_sandbox "a line that is not numbers is unreadable"
reply <<'R'
ready-for-agent + bug
  #52  Reconcile the webhook retry window

<!-- kit-startable: begin -->
bug: see #52 above
<!-- kit-startable: end -->
R
out="$(run bug)"
assert_lacks "$out" "taking #" "a number is not dug out of a malformed line"
assert_has "$out" "unreadable" "a malformed line stops the run"
end_sandbox

# ========================================================================
# AC · An issue's PR is resolved from GitHub's closing link, not its branch.
# ========================================================================

new_sandbox "a PR whose branch carries no issue number is still found"
SHIP_STUB_DELAY=6
reply <<'R'
<!-- kit-startable: begin -->
bug: 52
<!-- kit-startable: end -->
R
pr_list <<'J'
[{"number":61,"state":"OPEN","headRefName":"stop-swallowing-the-409",
  "closingIssuesReferences":[{"number":52}]}]
J
out="$(run bug)"
assert_has "$out" "shipped #52 as PR #61" "the closing link finds the PR"
assert_lacks "$out" "ANOMALY" "a clean ship is not reported as an anomaly"
end_sandbox

new_sandbox "a PR closing a different issue is not claimed"
SHIP_STUB_DELAY=6
reply <<'R'
<!-- kit-startable: begin -->
bug: 52
<!-- kit-startable: end -->
R
pr_list <<'J'
[{"number":61,"state":"OPEN","headRefName":"52-reconcile-the-retry-window",
  "closingIssuesReferences":[{"number":99}]}]
J
out="$(run bug)"
assert_lacks "$out" "shipped #52" "a branch prefix alone does not make it this issue's PR"
assert_has "$out" "ANOMALY" "a ticket with no PR linked to it is an anomaly"
end_sandbox

# ------------------------------------------------------------------------
echo
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ]
