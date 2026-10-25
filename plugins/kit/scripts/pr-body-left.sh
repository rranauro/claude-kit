#!/usr/bin/env bash
set -uo pipefail

# Writes the review round's left-for-the-person findings into the PR's body,
# at the end of its Instructions section, inside a marked block a later round
# replaces in place.
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

# Only lines outside code fences count as headings or markers. A Gist showing
# the block as an example, or a `# comment` in a fenced command, is the
# author's text, not the section's edge.
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

headings = ((n, re.fullmatch(r"(#{1,6}) Instructions[ \t]*", t)) for n, (i, t) in enumerate(live))
h, m = next(((n, m) for n, m in headings if m), (None, None))
if m is None:
    new = body + nl + nl + "## Instructions" + nl + nl + block
else:
    edge = re.compile(r"#{1,%d} " % len(m.group(1)))
    section = live[h + 1:]
    nxt = next((n for n, (i, t) in enumerate(section) if edge.match(t)), None)
    if nxt is not None:
        end, section = offsets[section[nxt][0]], section[:nxt]
    else:
        end = len(body)
    opened = next((n for n, (i, t) in enumerate(section) if t.strip() == OPEN), None)
    if opened is not None:
        closed = next((section[n] for n in range(opened + 1, len(section)) if section[n][1].strip() == CLOSE), None)
        if closed is None:
            sys.exit("pr-body-left: Instructions opens a kit-review-left block it never closes; not editing it")
        start = offsets[section[opened][0]]
        stop = offsets[closed[0]] + len(closed[1])
        new = body[:start] + block + body[stop:]
    else:
        # The section's own trailing blank lines stay where they are, ahead of
        # the next heading, so nothing the author wrote is re-spaced.
        kept = body[:end].rstrip("\r\n")
        new = kept + nl + nl + block + body[len(kept):]

open(out_path, "w").write(new)
# A round re-run over the same findings writes nothing, so the PR's history
# does not gain an edit that changed no byte.
sys.exit(3 if new == body else 0)
PY
status=$?
if [ "$status" -eq 3 ]; then
  echo "left: PR #$pr's Instructions already carry these items"
  exit 0
fi
[ "$status" -eq 0 ] || exit 1

gh pr edit "$pr" --body-file "$tmp/new" >/dev/null || {
  echo "pr-body-left: could not write PR #$pr's body" >&2
  exit 1
}

echo "left: $(grep -c '^[0-9][0-9]*\.' "$items") item(s) in PR #$pr's Instructions"
