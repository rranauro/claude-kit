#!/usr/bin/env bash
set -uo pipefail

# Writes the review round's left-for-the-person findings into a held PR's body,
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

usage() {
  echo "usage: pr-body-left.sh <pr> <items-file> [--repo owner/name]" >&2
  echo "  <items-file> holds the numbered items, already written as Markdown." >&2
  exit 2
}

[ $# -ge 2 ] || usage
pr="$1" items="$2"
shift 2
repo=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || usage; repo=(--repo "$2"); shift 2 ;;
    *) usage ;;
  esac
done

# An empty block would replace a previous round's items with nothing, which
# reads to the person as "nothing left to judge" when this round simply had no
# list to give.
if ! grep -q '[^[:space:]]' "$items" 2>/dev/null; then
  echo "pr-body-left: $items holds no items; nothing written" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

gh pr view "$pr" ${repo[@]+"${repo[@]}"} --json body --jq .body > "$tmp/body" || {
  echo "pr-body-left: could not read PR #$pr's body" >&2
  exit 1
}

python3 - "$tmp/body" "$items" "$tmp/new" <<'PY' || exit 1
import re, sys

body_path, items_path, out_path = sys.argv[1:4]
body = open(body_path).read()
# `--jq` adds one newline the body itself does not carry.
if body.endswith("\n"):
    body = body[:-1]
items = open(items_path).read().strip("\n")

OPEN, CLOSE = "<!-- kit-review-left -->", "<!-- /kit-review-left -->"
block = f"{OPEN}\n**Left for you by the review round** — each says what to look at and what settles it:\n\n{items}\n{CLOSE}"

start = body.find(OPEN)
if start != -1:
    end = body.find(CLOSE, start)
    if end == -1:
        sys.exit("pr-body-left: the body opens a kit-review-left block it never closes; not editing it")
    new = body[:start] + block + body[end + len(CLOSE):]
else:
    heading = re.search(r"^(#{1,6}) Instructions[ \t]*$", body, re.M)
    if heading is None:
        new = body + "\n\n## Instructions\n\n" + block
    else:
        level = len(heading.group(1))
        nxt = re.compile(r"^#{1,%d} " % level, re.M).search(body, heading.end())
        if nxt is None:
            new = body + "\n\n" + block
        else:
            # The section's own trailing blank lines stay where they are, ahead
            # of the next heading, so nothing the author wrote is re-spaced.
            section = body[:nxt.start()].rstrip("\n")
            gap = body[len(section):nxt.start()]
            new = section + "\n\n" + block + gap + body[nxt.start():]

open(out_path, "w").write(new)
PY

gh pr edit "$pr" ${repo[@]+"${repo[@]}"} --body-file "$tmp/new" >/dev/null || {
  echo "pr-body-left: could not write PR #$pr's body" >&2
  exit 1
}

echo "left: $(grep -c '^[0-9][0-9]*\.' "$items") item(s) in PR #$pr's Instructions"
