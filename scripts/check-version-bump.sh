#!/usr/bin/env bash
set -uo pipefail

# `claude plugin update` compares version numbers, not contents, so a payload
# change that ships under an unchanged version never reaches an installed
# session — nothing goes red and nothing is missing, the change simply does not
# arrive. This is the check that makes that impossible to merge.
#
# It lives here rather than in scripts/lint.sh because lint.sh also runs on push
# to main, where there is no base branch to diff against. A pull_request-only
# step in lint.yml is the only trigger where the question is even answerable.

BASE="${1:-origin/main}"
MANIFEST="plugins/kit/.claude-plugin/plugin.json"
PAYLOAD="plugins/kit/"

ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd "$ROOT"

die() { echo "  FAIL: $*" >&2; exit 1; }

# github.base_ref names a branch, not a ref that necessarily exists locally.
if git rev-parse --verify -q "origin/$BASE" >/dev/null; then base_ref="origin/$BASE"
elif git rev-parse --verify -q "$BASE" >/dev/null; then base_ref="$BASE"
else die "base ref '$BASE' does not exist — fetch it before running this"; fi

# The merge base, so commits that landed on the base after this branch was cut
# are not read as this branch's changes.
merge_base="$(git merge-base "$base_ref" HEAD)" ||
  die "no common history with '$base_ref' — the clone is too shallow to diff"

echo "==> plugin version against $base_ref"

changed="$(git diff --name-only "$merge_base" HEAD -- "$PAYLOAD")"
if [ -z "$changed" ]; then
  echo "  ok   nothing under $PAYLOAD changed, so no version cut is required"
  exit 0
fi

version_of() { # file-or-stdin-json
  python3 -c 'import json,sys; print(json.load(sys.stdin).get("version",""))' 2>/dev/null
}

head_version="$(version_of < "$MANIFEST")"
[ -n "$head_version" ] || die "$MANIFEST has no version"

# A manifest absent from the base is a plugin being added, which nothing can be
# behind.
if base_json="$(git show "$base_ref:$MANIFEST" 2>/dev/null)"; then
  base_version="$(printf '%s' "$base_json" | version_of)"
else
  base_version=""
fi

if [ -z "$base_version" ]; then
  echo "  ok   $MANIFEST is new on this branch ($head_version)"
  exit 0
fi

# Strictly greater, not merely different: a branch cut before a release carries
# a version the base has already passed, and merging it walks the published
# version backwards — the same failure as never bumping at all, pointed the
# other way.
highest="$(printf '%s\n%s\n' "$base_version" "$head_version" | sort -V | tail -1)"
if [ "$head_version" = "$base_version" ] || [ "$highest" != "$head_version" ]; then
  echo "  FAIL: $(echo "$changed" | wc -l | tr -d ' ') file(s) under $PAYLOAD changed, but" >&2
  echo "        $MANIFEST is $head_version and $base_ref is $base_version." >&2
  echo "        Cut a version — minor when the invocable surface moved, patch otherwise." >&2
  exit 1
fi

echo "  ok   $base_version -> $head_version"
