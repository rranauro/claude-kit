#!/usr/bin/env bash
set -uo pipefail

# Where the review round's left-for-the-person items land in a PR body, asserted
# with `gh` stubbed on PATH. The trap is the rest of the body: a held PR's reader
# trusts its Gist, criteria, evidence and reversibility as written, so the only
# bytes a round may change are the ones inside its own block.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PR_BODY_LEFT_SCRIPT:-$ROOT/plugins/kit/scripts/pr-body-left.sh}"
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

new_sandbox() {
  current="$1"
  echo "==> $current"
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$SANDBOX/bin"
  export BODY="$SANDBOX/body.md" OUT="$SANDBOX/out.md" EDIT_EXIT=0
  : > "$OUT"

  # `gh pr view --jq .body` prints the body with one newline added, as the real
  # one does; `gh pr edit --body-file` is the write under test.
  cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") cat "$BODY"; echo ;;
  "pr edit")
    while [ $# -gt 0 ]; do
      [ "$1" = "--body-file" ] && cp "$2" "$OUT"
      shift
    done
    exit "$EDIT_EXIT" ;;
esac
GH
  chmod +x "$SANDBOX/bin/gh"
  export PATH="$SANDBOX/bin:$ORIG_PATH"
  printf '1. Look at the badge on /blog with the filter open. Settled if it does not overlap.\n2. Decide whether /site_collections redirects. Settled by the owner saying yes or no.\n' > "$SANDBOX/items.md"
}

# Inline rather than a fixture file, so the expected bytes sit beside the
# assertion that compares them.
held_body() {
  printf '%s' '## Gist

Adds the thing.

## Acceptance Criteria

- met

## Evidence

- **Before:** red
  **After:** green

## Instructions

1. Open the page.

## Reversibility

**Undo:** easy'
}

# --- cases --------------------------------------------------------------

new_sandbox "puts the block at the top of the body, above the Gist"
held_body > "$BODY"
out="$("$SCRIPT" 7 "$SANDBOX/items.md")"; code=$?
assert_eq "$code" 0 "exits 0"
assert_has "$out" "2 item(s)" "reports what it left"
body="$(cat "$OUT")"
assert_eq "${body%%<!-- kit-review-left -->*}" "" "nothing comes before the block"
assert_eq "${body#*<!-- /kit-review-left -->}" "

$(held_body)" "the whole body follows the block unchanged"
assert_has "$body" "2. Decide whether /site_collections redirects." "carries the items"

new_sandbox "a later round replaces its block in place"
held_body > "$BODY"
"$SCRIPT" 7 "$SANDBOX/items.md" >/dev/null
cp "$OUT" "$BODY"
first="$(cat "$OUT")"
printf '1. Read the upload summary aloud. Settled if the owner accepts the wording.\n' > "$SANDBOX/items.md"
"$SCRIPT" 7 "$SANDBOX/items.md" >/dev/null
body="$(cat "$OUT")"
assert_count "$body" "<!-- kit-review-left -->" 1 "one block, not two"
assert_has "$body" "upload summary" "carries the new items"
case "$body" in *site_collections*) bad "drops the old items" ;; *) ok "drops the old items" ;; esac
assert_eq "${body%%<!-- kit-review-left -->*}" "" "the block stays at the top"
assert_eq "${body#*<!-- /kit-review-left -->}" "${first#*<!-- /kit-review-left -->}" "text after the block is unchanged"

new_sandbox "the same items again write nothing"
held_body > "$BODY"
"$SCRIPT" 7 "$SANDBOX/items.md" >/dev/null
cp "$OUT" "$BODY"
: > "$OUT"
out="$("$SCRIPT" 7 "$SANDBOX/items.md")"; code=$?
assert_eq "$code" 0 "exits 0"
assert_eq "$(cat "$OUT")" "" "edits nothing"
assert_has "$out" "already carries" "says so"

# A body an earlier version of this script wrote carries the block at the end
# of Instructions. Leaving it there splits the questions across two places.
old_body() {
  printf '%s' '## Gist

Adds the thing.

## Instructions

1. Open the page.

<!-- kit-review-left -->
**Left for you by the review round** — each says what to look at and what settles it:

1. Old question.
<!-- /kit-review-left -->

## Reversibility

**Undo:** easy'
}

new_sandbox "a block at the end of Instructions moves to the top"
old_body > "$BODY"
"$SCRIPT" 7 "$SANDBOX/items.md" >/dev/null
body="$(cat "$OUT")"
assert_count "$body" "<!-- kit-review-left -->" 1 "one block, not two"
assert_eq "${body%%<!-- kit-review-left -->*}" "" "the block is at the top"
assert_eq "${body#*<!-- /kit-review-left -->}" '

## Gist

Adds the thing.

## Instructions

1. Open the page.

## Reversibility

**Undo:** easy' "the old block is gone and the rest is as the author wrote it"

new_sandbox "a CRLF body keeps its line endings"
printf '## Gist\r\n\r\nx\r\n\r\n## Instructions\r\n\r\n1. Open it.\r\n\r\n<!-- kit-review-left -->\r\nold\r\n<!-- /kit-review-left -->\r\n\r\n## Reversibility\r\n\r\n**Undo:** easy' > "$BODY"
"$SCRIPT" 7 "$SANDBOX/items.md" >/dev/null
printf '## Gist\r\n\r\nx\r\n\r\n## Instructions\r\n\r\n1. Open it.\r\n\r\n## Reversibility\r\n\r\n**Undo:** easy' > "$SANDBOX/rest"
size=$(wc -c < "$SANDBOX/rest")
assert_eq "$(tail -c "$size" "$OUT" | od -c)" "$(od -c < "$SANDBOX/rest")" "the body after the block is byte-identical"
assert_eq "$(grep -c $'[^\r]$' "$OUT")" "1" "every line but the unterminated last ends CRLF"

new_sandbox "markers inside fences are not the block"
printf '%s' '## Gist

```text
<!-- kit-review-left -->
example
<!-- /kit-review-left -->
```

## Instructions

1. Open it.' > "$BODY"
"$SCRIPT" 7 "$SANDBOX/items.md" >/dev/null
body="$(cat "$OUT")"
assert_count "$body" "<!-- kit-review-left -->" 2 "the fenced example stays beside the new block"
assert_has "$body" "<!-- /kit-review-left -->

## Gist

\`\`\`text
<!-- kit-review-left -->
example" "the block lands at the top and the example is unchanged"

new_sandbox "no items is refused and writes nothing"
held_body > "$BODY"
: > "$SANDBOX/items.md"
"$SCRIPT" 7 "$SANDBOX/items.md" >/dev/null 2>&1; code=$?
[ "$code" -ne 0 ] && ok "exits non-zero" || bad "exits non-zero"
assert_eq "$(cat "$OUT")" "" "edits nothing"

new_sandbox "a refused write is a failure"
held_body > "$BODY"
export EDIT_EXIT=1
"$SCRIPT" 7 "$SANDBOX/items.md" >/dev/null 2>&1; code=$?
[ "$code" -ne 0 ] && ok "exits non-zero" || bad "exits non-zero"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
