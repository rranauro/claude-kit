#!/usr/bin/env bash
set -euo pipefail

# Report which adopted skills have upstream changes since their fork point.
#
# Reads the UPSTREAM sidecar that adopt-skill.sh writes into each adopted skill.
# Skills without a sidecar are ours outright and are skipped.

usage() {
  cat >&2 <<'EOF'
usage: check-upstream.sh [skill-name ...] [--fetch] [--stat]

  --fetch  git fetch the upstream repo first, so HEAD reflects the remote
  --stat   print a diffstat for each skill that changed

  With no skill names, checks every adopted skill.

env:
  SKILLS_REPO  upstream checkout (default: ~/dev/mattpocock)
EOF
  exit 2
}

do_fetch=false
show_stat=false
wanted=""

while [ $# -gt 0 ]; do
  case "$1" in
    --fetch)   do_fetch=true ;;
    --stat)    show_stat=true ;;
    -h|--help) usage ;;
    -*)        echo "error: unknown flag $1" >&2; usage ;;
    *)         wanted="$wanted $1" ;;
  esac
  shift
done

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_ROOT="$PLUGIN_ROOT/plugins/kit/skills"
SKILLS_REPO="${SKILLS_REPO:-$HOME/dev/mattpocock}"

[ -d "$SKILLS_REPO/.git" ] || {
  echo "error: no git repo at $SKILLS_REPO — set SKILLS_REPO to the upstream checkout" >&2
  exit 1
}

if $do_fetch; then
  echo "fetching $SKILLS_REPO..."
  git -C "$SKILLS_REPO" fetch --quiet origin
  # Compare against the remote branch: a local checkout can sit behind origin for
  # weeks, and reporting "up to date" off a stale HEAD is the failure that makes
  # this script worthless.
  head_ref="origin/HEAD"
else
  head_ref="HEAD"
fi

field() { sed -n "s/^$1: *//p" "$2" | head -1; }

changed=0
checked=0
stale=0

for dir in "$DEST_ROOT"/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"

  case "$wanted" in
    "") ;;
    *" $name"*) ;;
    *) continue ;;
  esac

  sidecar="$dir/UPSTREAM"
  [ -f "$sidecar" ] || continue

  sha="$(field sha "$sidecar")"
  rel="$(field path "$sidecar")"
  checked=$((checked + 1))

  if [ -z "$sha" ] || [ -z "$rel" ]; then
    echo "?? $name — UPSTREAM missing sha or path"
    stale=$((stale + 1))
    continue
  fi

  if ! git -C "$SKILLS_REPO" cat-file -e "$sha^{commit}" 2>/dev/null; then
    echo "?? $name — fork sha $sha not found in $SKILLS_REPO (try --fetch)"
    stale=$((stale + 1))
    continue
  fi

  # An upstream rename or delete leaves the recorded path matching nothing, so the
  # diff comes back empty and would otherwise read as "no changes" — the exact
  # wrong answer.
  if ! git -C "$SKILLS_REPO" cat-file -e "$head_ref:$rel" 2>/dev/null; then
    echo "!! $name — $rel no longer exists upstream (renamed or removed)"
    stale=$((stale + 1))
    continue
  fi

  if git -C "$SKILLS_REPO" diff --quiet "$sha..$head_ref" -- "$rel"; then
    echo "ok $name"
  else
    count="$(git -C "$SKILLS_REPO" rev-list --count "$sha..$head_ref" -- "$rel")"
    echo "CHANGED $name — $count commit(s) since $sha"
    changed=$((changed + 1))
    if $show_stat; then
      git -C "$SKILLS_REPO" diff --stat "$sha..$head_ref" -- "$rel" | sed 's/^/    /'
    fi
    echo "    git -C $SKILLS_REPO diff $sha..$head_ref -- $rel"
  fi
done

echo
if [ "$checked" -eq 0 ]; then
  echo "no adopted skills found in $DEST_ROOT"
  exit 0
fi
echo "$checked adopted, $changed with upstream changes, $stale needing attention"
[ "$changed" -eq 0 ] && [ "$stale" -eq 0 ]
