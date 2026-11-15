#!/usr/bin/env bash
set -uo pipefail

# Where a pinned PR's store records land in its body, asserted with `gh` stubbed
# on PATH and a store in a throwaway repo. The label means "a record was added",
# so the body is the only copy a reader without the store has: each record must
# arrive with its claim, check and witness whole, and nothing else the author
# wrote may move.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PR_BODY_PINNED_SCRIPT:-$ROOT/plugins/kit/scripts/pr-body-pinned.sh}"
ORIG_PATH="$PATH"

passed=0
failed=0
current=""

ok()  { echo "  ok   $current — $1"; passed=$((passed + 1)); }
bad() { echo "  FAIL $current — $1" >&2; failed=$((failed + 1)); }

assert_eq() { # actual expected label
  if [ "$1" = "$2" ]; then ok "$3"
  else bad "$3"; diff <(printf '%s\n' "$2") <(printf '%s\n' "$1") | sed 's/^/       /' >&2; fi
}

assert_has() { # haystack needle label
  case "$1" in
    *"$2"*) ok "$3" ;;
    *)      bad "$3"; printf '       expected to find: %s\n' "$2" >&2 ;;
  esac
}

assert_count() { # haystack needle n label
  local n
  n="$(printf '%s' "$1" | grep -cF -- "$2")"
  assert_eq "$n" "$3" "$4"
}

# Records go in by hand rather than through observe.sh's append, which runs a
# check and needs bash 4: this script only reads the store, and the witness is
# whatever the record says it is.
record() { # id claim check witness
  python3 - "$SANDBOX/repo/.claude/observations.jsonl" "$@" <<'PY'
import json, sys
path, rid, claim, check, witness = sys.argv[1:6]
with open(path, "a") as fh:
    fh.write(json.dumps({"v": 3, "id": rid, "claim": claim, "check": check, "witness": witness}) + "\n")
PY
}

new_sandbox() {
  current="$1"
  echo "==> $current"
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$SANDBOX/bin" "$SANDBOX/repo/.claude"
  git -C "$SANDBOX/repo" init -q
  : > "$SANDBOX/repo/.claude/observations.jsonl"
  export BODY="$SANDBOX/body.md" OUT="$SANDBOX/out.md" LABELS="$SANDBOX/labels" EDIT_EXIT=0 LABEL_EXIT=0
  : > "$OUT"; : > "$LABELS"

  cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") cat "$BODY"; echo ;;
  "pr edit")
    while [ $# -gt 0 ]; do
      case "$1" in
        --body-file) [ "$EDIT_EXIT" -eq 0 ] || exit "$EDIT_EXIT"; cp "$2" "$OUT" ;;
        --add-label) [ "$LABEL_EXIT" -eq 0 ] || exit "$LABEL_EXIT"; echo "$2" >> "$LABELS" ;;
      esac
      shift
    done ;;
esac
GH
  chmod +x "$SANDBOX/bin/gh"
  export PATH="$SANDBOX/bin:$ORIG_PATH"
  cd "$SANDBOX/repo" || exit 1
}

pr_body() {
  printf '%s' '## Gist

Adds the thing.

## Reversibility

**Undo:** easy'
}

# --- cases --------------------------------------------------------------

new_sandbox "appends the record after the body, whole"
pr_body > "$BODY"
record docs-name-a-missing-step "docs/a.md names a step no command runs" "grep -c 'step five' docs/a.md" "2"
out="$("$SCRIPT" 7 docs-name-a-missing-step)"; code=$?
assert_eq "$code" 0 "exits 0"
assert_has "$out" "1 record(s)" "reports what it pinned"
body="$(cat "$OUT")"
assert_eq "${body%%<!-- kit-pinned -->*}" "$(pr_body)

" "the author's body comes first, unchanged"
assert_has "$body" "docs/a.md names a step no command runs" "carries the claim"
assert_has "$body" "grep -c 'step five' docs/a.md" "carries the check"
assert_has "$body" "<!-- kit-pinned: docs-name-a-missing-step -->" "marks the record by its slug"
assert_eq "${body##*<!-- /kit-pinned -->}" "" "the block ends the body"
assert_eq "$(cat "$LABELS")" "kit-pinned" "labels the PR once the body is written"

new_sandbox "a later record joins the block, and the earlier one stays as written"
pr_body > "$BODY"
record first-claim "the first claim" "echo one" "one"
record second-claim "the second claim" "echo two" "two"
"$SCRIPT" 7 first-claim >/dev/null
cp "$OUT" "$BODY"
first="$(cat "$OUT")"
"$SCRIPT" 7 second-claim >/dev/null
body="$(cat "$OUT")"
assert_count "$body" "<!-- kit-pinned -->" 1 "one block, not two"
assert_has "$body" "the second claim" "carries the new record"
assert_eq "${body%%<!-- kit-pinned: second-claim -->*}" "${first%%<!-- /kit-pinned -->*}" "everything before it is unchanged"

new_sandbox "a record already pinned writes nothing"
pr_body > "$BODY"
record first-claim "the first claim" "echo one" "one"
"$SCRIPT" 7 first-claim >/dev/null
cp "$OUT" "$BODY"
: > "$OUT"
out="$("$SCRIPT" 7 first-claim)"; code=$?
assert_eq "$code" 0 "exits 0"
assert_eq "$(cat "$OUT")" "" "edits nothing"
assert_has "$out" "already carries" "says so"
assert_eq "$(cat "$LABELS")" "kit-pinned
kit-pinned" "labels it again, in case the last run lost the label"

new_sandbox "a witness carrying a fence cannot close the block's"
pr_body > "$BODY"
record fenced "a fenced witness" "cat x.md" '```sh
echo hi
```'
"$SCRIPT" 7 fenced >/dev/null
body="$(cat "$OUT")"
assert_has "$body" '````text
```sh
echo hi
```
````' "the witness sits in a longer fence"

new_sandbox "an empty witness says so"
pr_body > "$BODY"
record absent "a file is gone" "ls gone 2>/dev/null" ""
"$SCRIPT" 7 absent >/dev/null
assert_has "$(cat "$OUT")" "(empty)" "names the absence"

new_sandbox "markers inside the author's fences are not the block"
printf '%s' '## Gist

```text
<!-- kit-pinned -->
example
<!-- /kit-pinned -->
```' > "$BODY"
record first-claim "the first claim" "echo one" "one"
"$SCRIPT" 7 first-claim >/dev/null
body="$(cat "$OUT")"
assert_count "$body" "<!-- kit-pinned -->" 2 "the fenced example stays beside the new block"
assert_eq "${body##*<!-- /kit-pinned -->}" "" "the new block ends the body"

new_sandbox "a slug the store does not hold is refused and writes nothing"
pr_body > "$BODY"
"$SCRIPT" 7 no-such-record >/dev/null 2>&1; code=$?
assert_eq "$code" 1 "exits 1"
assert_eq "$(cat "$OUT")" "" "edits nothing"
assert_eq "$(cat "$LABELS")" "" "applies no label"

new_sandbox "no slug is a usage error"
"$SCRIPT" 7 >/dev/null 2>&1; code=$?
assert_eq "$code" 2 "exits 2"

new_sandbox "a refused body write is a failure, and labels nothing"
pr_body > "$BODY"
record first-claim "the first claim" "echo one" "one"
export EDIT_EXIT=1
"$SCRIPT" 7 first-claim >/dev/null 2>&1; code=$?
assert_eq "$code" 1 "exits 1"
assert_eq "$(cat "$LABELS")" "" "applies no label"

new_sandbox "a refused label is said, and the body keeps its records"
pr_body > "$BODY"
record first-claim "the first claim" "echo one" "one"
export LABEL_EXIT=1
err="$("$SCRIPT" 7 first-claim 2>&1 >/dev/null)"; code=$?
assert_eq "$code" 4 "exits 4"
assert_has "$err" "could not be applied" "names the label that did not land"
assert_has "$(cat "$OUT")" "the first claim" "the body was written"

new_sandbox "the project's spelling of the label"
pr_body > "$BODY"
record first-claim "the first claim" "echo one" "one"
"$SCRIPT" --label "Status: Pinned" 7 first-claim >/dev/null
assert_eq "$(cat "$LABELS")" "Status: Pinned" "applies that label"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
