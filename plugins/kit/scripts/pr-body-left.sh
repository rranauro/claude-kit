#!/usr/bin/env bash
set -uo pipefail

# Writes the review round's left-for-the-person findings at the top of the PR's
# body, above the Gist, inside a marked block a later round replaces in place.
# They are the questions holding the PR, so they come before anything else the
# person reads.
#
# A script rather than prose in /kit:review-copilot because the rest of the body
# must come back byte-for-byte. The person holding the PR reads its Gist,
# criteria, evidence and reversibility as the author wrote them, and a model
# re-emitting a whole body to add one list eventually rewords a line nobody
# asked it to touch — a change no reader would think to diff for. Here the only
# bytes that move are the block's own, and `tests/pr-body-left.sh` holds it to
# that.

if [ $# -ne 2 ]; then
  echo "usage: pr-body-left.sh <pr> <items-file>" >&2
  echo "  <items-file> holds the numbered items, already written as Markdown." >&2
  exit 2
fi
pr="$1" items="$2"

# An empty block would replace a previous round's items with nothing, which
# reads to the person as "nothing left to judge" when this round simply had no
# list to give.
if ! grep -q '[^[:space:]]' "$items" 2>/dev/null; then
  echo "pr-body-left: $items holds no items; nothing written" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

gh pr view "$pr" --json body --jq .body > "$tmp/body" || {
  echo "pr-body-left: could not read PR #$pr's body" >&2
  exit 1
}

python3 - "$tmp/body" "$items" "$tmp/new" <<'PY'
import re, sys

body_path, items_path, out_path = sys.argv[1:4]
# newline="" keeps a body written in GitHub's editor CRLF; text mode would
# rewrite every line of it.
body = open(body_path, newline="").read()
# `--jq` adds one newline the body itself does not carry.
if body.endswith("\n"):
    body = body[:-1]
nl = "\r\n" if "\r\n" in body else "\n"
items = nl.join(open(items_path).read().strip("\n").splitlines())

OPEN, CLOSE = "<!-- kit-review-left -->", "<!-- /kit-review-left -->"
block = nl.join([OPEN, "**Left for you by the review round** — each says what to look at and what settles it:", "", items, CLOSE])

# Only lines outside code fences count as markers. A Gist showing the block as
# an example is the author's text, not a block to replace.
lines = body.splitlines(keepends=True)
offsets = [0]
for line in lines:
    offsets.append(offsets[-1] + len(line))
live, fence = [], None
for i, line in enumerate(lines):
    text = line.rstrip("\r\n")
    m = re.match(r" {0,3}(`{3,}|~{3,})", text)
    if fence:
        if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not text.strip(m.group(1)[0] + " \t"):
            fence = None
    elif m:
        fence = m.group(1)
    else:
        live.append((i, text))

opened = next((n for n, (i, t) in enumerate(live) if t.strip() == OPEN), None)
rest = body
if opened is not None:
    closed = next((live[n] for n in range(opened + 1, len(live)) if live[n][1].strip() == CLOSE), None)
    if closed is None:
        sys.exit("pr-body-left: the body opens a kit-review-left block it never closes; not editing it")
    start = offsets[live[opened][0]]
    stop = offsets[closed[0]] + len(closed[1])
    # A block found below the top was written at the end of Instructions,
    # after a blank line of its own; taking that line too leaves the section as
    # the author wrote it.
    rest = (body[:start].rstrip("\r\n") + body[stop:]).lstrip("\r\n")

new = block + (nl + nl + rest if rest else "")

open(out_path, "w").write(new)
# A round re-run over the same findings writes nothing, so the PR's history
# does not gain an edit that changed no byte.
sys.exit(3 if new == body else 0)
PY
status=$?
if [ "$status" -eq 3 ]; then
  echo "left: the top of PR #$pr's body already carries these items"
  exit 0
fi
[ "$status" -eq 0 ] || exit 1

gh pr edit "$pr" --body-file "$tmp/new" >/dev/null || {
  echo "pr-body-left: could not write PR #$pr's body" >&2
  exit 1
}

echo "left: $(grep -c '^[0-9][0-9]*\.' "$items") item(s) at the top of PR #$pr's body"
