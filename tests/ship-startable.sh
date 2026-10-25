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

assert_eq() { # actual expected label
  if [ "$1" = "$2" ]; then ok "$3"
  else bad "$3"; printf '       expected: %s\n       actual:   %s\n' "$2" "$1" >&2; fi
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
  # the plugin failed to resolve. A `--bg` launch does its work at once — writing
  # whichever reply file its prompt names — and `agents --json` then reports
  # every session it launched as done. Each call is logged with its launcher and
  # whether its grant may file issues, which are what the drain criteria are about.
  cat > "$SANDBOX/bin/claude" <<'CLAUDE'
#!/usr/bin/env bash
if [ "${1-}" = agents ]; then
  python3 -c '
import json, sys
names = [l.strip() for l in open(sys.argv[1])] if len(sys.argv) > 1 else []
print(json.dumps([{"name": n, "state": "done"} for n in names]))
' $( [ -f "$SESSIONS" ] && echo "$SESSIONS" )
  exit 0
fi
[ "${1-}" = stop ] && exit 0

mode="" prompt="" name="" settings=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p)                prompt="$2"; mode=p; shift 2 ;;
    --bg)              mode=bg; shift ;;
    --name)            name="$2"; shift 2 ;;
    --settings)        settings="$2"; shift 2 ;;
    --model|--plugin-dir|--permission-mode|--add-dir) shift 2 ;;
    *)                 prompt="$1"; shift ;;
  esac
done
files=no write=none
if [ -n "$settings" ]; then
  python3 -c '
import json, sys
allow = json.load(open(sys.argv[1]))["permissions"]["allow"]
sys.exit(0 if any("gh issue create" in a for a in allow) else 1)
' "$settings" && files=yes
  write="$(python3 -c '
import json, sys
allow = json.load(open(sys.argv[1]))["permissions"]["allow"]
w = [a for a in allow if a == "Write" or a.startswith("Write(")]
print("bare" if "Write" in w else ",".join(w) or "none")
' "$settings")"
fi
echo "$mode files-issues=$files write=$write $prompt" >> "$CALLS"

after() { printf '%s\n' "$prompt" | sed -n "s/.*$1 \([^ ]*\).*/\1/p"; }
case "$prompt" in
  */kit:list*)
    out="$(after --offer-file)"
    if [ -n "$out" ]; then cp "$REPLY_FILE" "$out"; else cat "$REPLY_FILE"; fi ;;
  */kit:observe\ file*)
    cp "$FILE_REPLY" "$(after --reply)" ;;
  *)
    sleep "${SHIP_STUB_DELAY:-0}"; echo "ship-ticket stub ran" ;;
esac
[ "$mode" = bg ] && echo "$name" >> "$SESSIONS"
exit 0
CLAUDE
  chmod +x "$SANDBOX/bin/claude"

  # Answers the PR listing from a fixture, an issue's labels from a per-issue
  # file, and every other lookup with an empty, well-formed result — enough for
  # the script's preflight, and enough that a test says nothing about GitHub
  # state it did not set. Writes are logged, never performed.
  cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
case "$*" in
  *"pr list --state all"*) cat "$PR_LIST_FIXTURE" ;;
  "issue view "*" --json labels"*)
    n="${3-}"; [ -f "$LABELS_DIR/$n" ] && cat "$LABELS_DIR/$n" ;;
  "issue view "*" --json body"*)
    [ -n "${GH_BODY_FAILS:-}" ] && exit 1
    echo "the filed body" ;;
  *--json*)                echo '[]' ;;
  *)                       : ;;
esac
GH
  chmod +x "$SANDBOX/bin/gh"

  CALLS="$SANDBOX/claude-calls.log"
  GH_CALLS="$SANDBOX/gh-calls.log"
  SESSIONS="$SANDBOX/sessions"
  FILE_REPLY="$SANDBOX/file-reply.txt"
  LABELS_DIR="$SANDBOX/labels"
  mkdir -p "$LABELS_DIR"
  : > "$CALLS"; : > "$GH_CALLS"
  export CALLS GH_CALLS SESSIONS FILE_REPLY LABELS_DIR
  # The background poll, shortened, but kept at the script's floor: a session
  # that ends faster than that is the anomaly a test here is not about.
  export SHIP_STARTABLE_BG_POLL=5

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
file_reply() { cat > "$FILE_REPLY"; }
labels_of() { cat > "$LABELS_DIR/$1"; }
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

# ========================================================================
# AC · A drained label files one record waiting on a ticket, ships it by
#      number, and drops the record once the issue has a PR or a park.
# ========================================================================

OBSERVE="$ROOT/plugins/kit/scripts/observe.sh"

observe() { # extra-args...
  (cd "$MAIN" && "$OBSERVE" \
    --by "kit:grilling" \
    --check "grep -c hello README.md" \
    --surfaced "a pass saw it" \
    --who agent \
    --affected "an agent reads the wrong thing" \
    "$@" >/dev/null 2>&1)
}

STORE_OF() { cat "$MAIN/.claude/observations.jsonl" 2>/dev/null; }

seed_store() {
  observe --claim "a call only the owner can make" --waiting owner \
    --action "the owner decides whether this is worth doing"
  observe --claim "README says hello where it should say goodbye" --waiting ticket \
    --action "a ticket that changes the README greeting" \
    --decision "change it to goodbye"
}

drain() { run bug --observations; }

new_sandbox "a drained label files the oldest ticket record and ships it by number"
seed_store
owner_line="$(STORE_OF | grep 'only the owner')"
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
file_reply <<'F'
filed: 90
F
pr_list <<'J'
[{"number":91,"state":"OPEN","closingIssuesReferences":[{"number":90}]}]
J
out="$(drain)"
assert_has "$(cat "$CALLS")" "/kit:observe file readme-says-hello" "the ticket record is filed"
assert_lacks "$(cat "$CALLS")" "/kit:observe file a-call-only" "the owner's record is not"
assert_has "$(cat "$CALLS")" "/kit:ship-ticket 90 unattended" "the filed issue is shipped by its number"
assert_has "$out" "#90 -> PR #91" "the summary names the issue and its PR"
assert_has "$out" "from readme-says-hello" "and the record it came from"
assert_lacks "$(STORE_OF)" "README says hello" "the filed record is gone from the store"
assert_eq "$(STORE_OF | grep 'only the owner')" "$owner_line" "the owner's record is untouched"
assert_has "$out" "records remaining: 1" "the summary counts what is left"
assert_has "$out" "cap (1) reached" "a filed record counts toward the cap"
end_sandbox

new_sandbox "every call a draining run makes is a background session"
seed_store
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
file_reply <<'F'
filed: 90
F
pr_list <<'J'
[{"number":91,"state":"OPEN","closingIssuesReferences":[{"number":90}]}]
J
out="$(drain)"
assert_lacks "$(cat "$CALLS")" "p files-issues" "nothing runs on -p"
assert_has "$(grep '/kit:list' "$CALLS")" "bg " "the list call is a background session"
assert_has "$out" "claude attach" "the operator is told how to attach"
end_sandbox

new_sandbox "only the filing session may file an issue"
seed_store
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
file_reply <<'F'
filed: 90
F
pr_list <<'J'
[{"number":91,"state":"OPEN","closingIssuesReferences":[{"number":90}]}]
J
out="$(drain)"
assert_has "$(grep '/kit:observe file' "$CALLS")" "files-issues=yes" "filing runs under a grant that files"
assert_has "$(grep '/kit:ship-ticket' "$CALLS")" "files-issues=no" "shipping does not"
assert_has "$(grep '/kit:list' "$CALLS")" "files-issues=no" "and neither does listing"
assert_lacks "$(grep '/kit:observe file' "$CALLS")" "write=bare" "the filing grant cannot write anywhere it likes"
assert_has "$(grep '/kit:observe file' "$CALLS")" "write=Write(//" "only under the run's reply directory"
end_sandbox

new_sandbox "a record that cannot be dropped stops the run before it is filed again"
seed_store
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
file_reply <<'F'
filed: 90
F
pr_list <<'J'
[{"number":91,"state":"OPEN","closingIssuesReferences":[{"number":90}]}]
J
chmod 555 "$MAIN/.claude"
out="$(drain)"
chmod 755 "$MAIN/.claude"
assert_has "$out" "could not be dropped after #90" "the run stops naming the record"
assert_eq "$(grep -c '/kit:observe file' "$CALLS")" "1" "and files it only once"
end_sandbox

new_sandbox "a filed issue whose body cannot be read is not overwritten"
seed_store
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
file_reply <<'F'
filed: 90
F
GH_BODY_FAILS=1 out="$(GH_BODY_FAILS=1 drain)"
assert_lacks "$(cat "$GH_CALLS")" "issue edit 90" "the body is never written back"
assert_has "$(STORE_OF)" "README says hello" "the record is kept"
assert_has "$out" "could not be parked" "and the run stops saying so"
end_sandbox

new_sandbox "a record the filing session declines stays in the store"
seed_store
before="$(STORE_OF)"
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
file_reply <<'F'
declined: no acceptance criteria can be stated for it
F
out="$(drain)"
assert_eq "$(STORE_OF)" "$before" "the store is unchanged"
assert_lacks "$(cat "$CALLS")" "/kit:ship-ticket" "nothing is shipped"
assert_has "$out" "declined: 1" "the summary counts the decline"
assert_has "$out" "no acceptance criteria can be stated" "with its reason"
assert_has "$out" "done: nothing startable" "and the run ends rather than refiling it"
end_sandbox

new_sandbox "a decline moves on to the next record without asking the label again"
seed_store
observe --claim "README still greets the reader" --waiting ticket \
  --action "a ticket that rewrites the README greeting"
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
file_reply <<'F'
declined: the premise is gone
F
out="$(drain)"
assert_eq "$(grep -c '/kit:observe file' "$CALLS")" "2" "both ticket records are offered for filing"
assert_eq "$(grep -c '/kit:list' "$CALLS")" "1" "on one reading of the label"
assert_has "$out" "declined: 2" "and both declines are reported"
end_sandbox

new_sandbox "a record whose check has moved is not filed"
seed_store
echo goodbye > "$MAIN/README.md"
before="$(STORE_OF)"
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
out="$(drain)"
assert_lacks "$(cat "$CALLS")" "/kit:observe file" "no filing session runs"
assert_eq "$(STORE_OF)" "$before" "the store is unchanged"
end_sandbox

new_sandbox "a filed ticket that parks drops its record"
seed_store
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
file_reply <<'F'
filed: 90
F
labels_of 90 <<'L'
kit-blocked
L
out="$(drain)"
assert_lacks "$(STORE_OF)" "README says hello" "the record is gone"
assert_has "$out" "#90 (from readme-says-hello-where-it-should-say-goodbye)" "the park is reported against its record"
assert_lacks "$(cat "$GH_CALLS")" "issue comment 90" "the runner adds no park of its own"
end_sandbox

new_sandbox "a filed ticket the run cannot trace is parked by the runner"
seed_store
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
file_reply <<'F'
filed: 90
F
out="$(drain)"
assert_has "$(cat "$GH_CALLS")" "issue comment 90" "the runner comments on the issue"
assert_has "$(cat "$GH_CALLS")" "issue edit 90 --add-label kit-blocked" "and labels it kit-blocked"
assert_lacks "$(STORE_OF)" "README says hello" "the record is dropped, since the issue carries it"
assert_has "$out" "#90 (from readme-says-hello" "the park is reported"
end_sandbox

new_sandbox "a filing session that leaves no reply files nothing it is not told of"
seed_store
before="$(STORE_OF)"
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
: > "$FILE_REPLY"
out="$(drain)"
assert_eq "$(STORE_OF)" "$before" "the store is unchanged"
assert_lacks "$(cat "$CALLS")" "/kit:ship-ticket" "nothing is shipped"
assert_has "$out" "readme-says-hello" "the record is reported as not filed"
end_sandbox

new_sandbox "without --observations the store is never read"
seed_store
before="$(STORE_OF)"
reply <<'R'
<!-- kit-startable: begin -->
bug:
<!-- kit-startable: end -->
R
out="$(run bug)"
assert_lacks "$(cat "$CALLS")" "/kit:observe" "no filing session runs"
assert_eq "$(STORE_OF)" "$before" "the store is unchanged"
assert_lacks "$out" "records remaining" "and the summary says nothing about it"
end_sandbox

new_sandbox "under --bg the offer block is read from the file the session wrote"
reply <<'R'
<!-- kit-startable: begin -->
bug: 52
<!-- kit-startable: end -->
R
out="$(run bug --bg)"
assert_has "$out" "taking #52" "the line in the reply file is what is taken"
end_sandbox

# ------------------------------------------------------------------------
echo
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ]
