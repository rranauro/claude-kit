#!/usr/bin/env bash
set -uo pipefail

# Copies observation-store records into a marked block at the end of a PR's
# body, one entry per record with its claim, check and witness. `kit-pinned`
# claims a record was added; the store lives on one machine, so this copy is
# what the label means everywhere else (ADR 0005).
#
# A script for the reason pr-body-left.sh is one: the rest of the body must come
# back byte-for-byte, and a model re-emitting a whole body eventually rewords a
# line nobody asked it to touch. Records already in the block are left as
# written, so a re-run adds only what is new. `tests/pr-body-pinned.sh` holds it
# to that.

if [ $# -lt 2 ]; then
  echo "usage: pr-body-pinned.sh <pr> <slug> [<slug> ...]" >&2
  echo "  each <slug> is a record in the observation store (observe.sh show)." >&2
  exit 2
fi
pr="$1"; shift

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Every slug resolves before anything is written: a block missing one record
# reads as complete, and the pass would pin on it.
OBSERVE="$(cd "$(dirname "$0")" && pwd)/observe.sh"
: > "$tmp/records"
for slug in "$@"; do
  "$OBSERVE" show "$slug" > "$tmp/one" 2>/dev/null || {
    echo "pr-body-pinned: the store holds no record $slug; nothing written" >&2
    exit 1
  }
  python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))' "$tmp/one" >> "$tmp/records"
done

gh pr view "$pr" --json body --jq .body > "$tmp/body" || {
  echo "pr-body-pinned: could not read PR #$pr's body" >&2
  exit 1
}

added="$(python3 - "$tmp/body" "$tmp/records" "$tmp/new" <<'PY'
import json, re, sys

body_path, records_path, out_path = sys.argv[1:4]
body = open(body_path, newline="").read()
if body.endswith("\n"):
    body = body[:-1]
nl = "\r\n" if "\r\n" in body else "\n"
records = [json.loads(l) for l in open(records_path) if l.strip()]

OPEN, CLOSE = "<!-- kit-pinned -->", "<!-- /kit-pinned -->"
ENTRY = "<!-- kit-pinned: {} -->"

def fenced(text):
    # A fence longer than any backtick run inside, so a witness that is itself
    # Markdown cannot close it.
    runs = [len(m) for m in re.findall(r"`+", text)]
    fence = "`" * max(3, max(runs, default=0) + 1)
    return [fence + "text", *(text.splitlines() or ["(empty)"]), fence]

def entry(r):
    return [
        ENTRY.format(r["id"]),
        "**" + " ".join((r.get("claim") or "").split()) + "**",
        "",
        "Check, run from the repository root:",
        "",
        *fenced(r.get("check") or ""),
        "",
        "Witness when it was recorded:",
        "",
        *fenced(r.get("witness") or ""),
    ]

# Markers count only outside code fences, so an author's example is left alone.
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
        live.append((i, text.strip()))

opened = next((n for n, (i, t) in enumerate(live) if t == OPEN), None)
if opened is None:
    fresh = records
    if not fresh:
        sys.exit(3)
    block = [OPEN, "**Pinned to the observation store** — each record a pass working this PR added, as the store holds it:", ""]
    for r in fresh:
        block += entry(r) + [""]
    block.append(CLOSE)
    new = (body + nl + nl if body else "") + nl.join(block)
else:
    closed = next((live[n] for n in range(opened + 1, len(live)) if live[n][1] == CLOSE), None)
    if closed is None:
        sys.exit("pr-body-pinned: the body opens a kit-pinned block it never closes; not editing it")
    have = {t for i, t in live[opened + 1:] if t.startswith("<!-- kit-pinned: ")}
    fresh = [r for r in records if ENTRY.format(r["id"]) not in have]
    if not fresh:
        sys.exit(3)
    at = offsets[closed[0]]
    added = []
    for r in fresh:
        added += entry(r) + [""]
    new = body[:at] + nl.join(added) + nl + body[at:]

open(out_path, "w", newline="").write(new)
print(len(fresh))
PY
)"
status=$?
if [ "$status" -eq 3 ]; then
  echo "pinned: PR #$pr's body already carries these records"
  exit 0
fi
[ "$status" -eq 0 ] || exit 1

gh pr edit "$pr" --body-file "$tmp/new" >/dev/null || {
  echo "pr-body-pinned: could not write PR #$pr's body" >&2
  exit 1
}

echo "pinned: $added record(s) added to PR #$pr's body"
