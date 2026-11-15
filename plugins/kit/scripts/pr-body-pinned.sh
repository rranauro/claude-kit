#!/usr/bin/env bash
set -uo pipefail

# Copies observation-store records into a marked block at the end of a PR's
# body, one entry per record with its claim, check and witness, then labels the
# PR `kit-pinned`. The label claims a record was added; the store lives on one
# machine, so this copy is what the label means everywhere else (ADR 0005). The
# label is applied here, and only after the body write lands, so no caller can
# apply one without the other.
#
# A script for the reason pr-body-left.sh is one: the rest of the body must come
# back byte-for-byte, and a model re-emitting a whole body eventually rewords a
# line nobody asked it to touch. Records already in the block are left as
# written, so a re-run adds only what is new. `tests/pr-body-pinned.sh` holds it
# to that.

# A project that says it has no pin label still gets the copy: the record is
# the decision, and the label only its mark (docs/labels.md).
label="kit-pinned"
case "${1-}" in
  --label)    label="${2-}"; if [ -n "$label" ]; then shift 2; else set --; fi ;;
  --no-label) label=""; shift ;;
esac
if [ $# -lt 2 ]; then
  echo "usage: pr-body-pinned.sh [--label <name> | --no-label] <pr> <slug> [<slug> ...]" >&2
  echo "  each <slug> is a record in the observation store (observe.sh show);" >&2
  echo "  --label is the project's spelling of kit-pinned; --no-label copies only," >&2
  echo "  for a project that has no pin label." >&2
  exit 2
fi
pr="$1"; shift

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Every slug resolves before anything is written: a block missing one record
# reads as complete, and the label would claim it.
OBSERVE="$(cd "$(dirname "$0")" && pwd)/observe.sh"
n=0
for slug in "$@"; do
  n=$((n + 1))
  "$OBSERVE" show "$slug" > "$tmp/record.$n" 2>/dev/null || {
    echo "pr-body-pinned: the store holds no record $slug; nothing written" >&2
    exit 1
  }
done

gh pr view "$pr" --json body --jq .body > "$tmp/body" || {
  echo "pr-body-pinned: could not read PR #$pr's body" >&2
  exit 1
}

added="$(python3 - "$tmp/body" "$tmp/new" "$tmp"/record.* <<'PY'
import json, re, sys

body_path, out_path, *record_paths = sys.argv[1:]
# newline="" keeps a body written in GitHub's editor CRLF.
body = open(body_path, newline="").read()
# `--jq` adds one newline the body itself does not carry.
if body.endswith("\n"):
    body = body[:-1]
nl = "\r\n" if "\r\n" in body else "\n"
records = [json.load(open(p)) for p in record_paths]

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
        "",
    ]

# Markers count only outside code fences, so an author's example is left alone.
lines = body.splitlines(keepends=True)
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
        # Not stripped: this script writes its markers at column zero, and an
        # indented one is an author's example inside a list.
        live.append((i, text.rstrip()))

opened = next((n for n, (i, t) in enumerate(live) if t == OPEN), None)
closed = None
if opened is not None:
    closed = next((live[n] for n in range(opened + 1, len(live)) if live[n][1] == CLOSE), None)
    if closed is None:
        sys.exit("pr-body-pinned: the body opens a kit-pinned block it never closes; not editing it")
have = {t for i, t in live[opened + 1:]} if opened is not None else set()
fresh = [r for r in records if ENTRY.format(r["id"]) not in have]
if not fresh:
    sys.exit(3)
added = [l for r in fresh for l in entry(r)]

if closed is None:
    # Appended inside a fence the author never closed, the block would be
    # invisible to the next run, which would append the same records again.
    if fence:
        sys.exit("pr-body-pinned: the body ends inside an unclosed code fence; not editing it")
    head = [OPEN, "**Pinned to the observation store** — each record a pass working this PR added, as the store holds it:", ""]
    new = (body + nl + nl if body else "") + nl.join(head + added + [CLOSE])
else:
    at = sum(len(l) for l in lines[:closed[0]])
    new = body[:at] + nl.join(added) + nl + body[at:]

open(out_path, "w", newline="").write(new)
print(len(fresh))
PY
)"
status=$?
if [ "$status" -eq 3 ]; then
  echo "pinned: PR #$pr's body already carries these records"
elif [ "$status" -ne 0 ]; then
  exit 1
elif gh pr edit "$pr" --body-file "$tmp/new" >/dev/null; then
  echo "pinned: $added record(s) added to PR #$pr's body"
else
  echo "pr-body-pinned: could not write PR #$pr's body; ${label:-no label} not applied" >&2
  exit 1
fi

[ -n "$label" ] || exit 0

# Applied on a re-run too: the last one may have written the body and lost the
# label, and adding a label the PR already carries changes nothing.
gh pr edit "$pr" --add-label "$label" >/dev/null || {
  echo "pr-body-pinned: the records are in PR #$pr's body, but $label could not be applied; \`gh label create $label\` is the repo owner's fix" >&2
  exit 4
}
echo "pinned: PR #$pr carries $label"
