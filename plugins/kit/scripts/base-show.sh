#!/usr/bin/env bash
set -uo pipefail

# Reads one file out of a revision's tree, following the symlinks stored in that
# tree, and writes the blob to stdout or to <out>.
#
# A script rather than `git show <rev>:<path>` because a path lookup inside a
# commit does not cross a symlink: a project that tracks `.claude/skills` as a
# link to a directory elsewhere has a skill the base branch holds and `git show`
# calls missing. Rather than resolving links here, git is asked to — a link out
# of the repository, a loop and a target that is not there all come back as
# git's own verdicts, so "outside the repo is missing" cannot drift from what
# git actually followed. And it is a script rather than a pipe into
# `git cat-file --batch` because that prefixes a header and appends a newline,
# which every reader would then have to strip, and a reader that mistakes
# `symlink` for content follows a link the rule says to treat as missing.
# `tests/base-show.sh` holds it to the bytes.
#
# <rev> is always `origin/<base>`. Links are resolved inside that tree alone, so
# a pass whose own branch retargets one, or edits the file it points to, still
# reads the base's version.

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "usage: base-show.sh <rev> <path> [<out>]" >&2
  echo "  exits 0 only for a blob; anything else exits 1 with 'missing: <git's word> <path>'." >&2
  exit 2
fi
rev="$1" path="$2" out="${3:-}"

missing() {
  echo "missing: $1 $path" >&2
  exit 1
}

# Only the header line matters here. The blob itself is read below by its id, so
# no byte of it passes through a shell variable or a header parser.
header="$(printf '%s:%s\n' "$rev" "$path" | git cat-file --batch-check --follow-symlinks 2>/dev/null | head -n 1)"
[ -n "$header" ] || missing "unreadable"

set -- $header
case "$1" in
  symlink|dangling|loop|notdir) missing "$1" ;;
esac
[ "$2" = "blob" ] || missing "$2"

# A blob is written to <out> only once git has said it is one, so a refusal
# leaves no file for a caller to run by mistake.
if [ -n "$out" ]; then
  git cat-file blob "$1" > "$out" || missing "unwritable"
else
  git cat-file blob "$1" || missing "unreadable"
fi
