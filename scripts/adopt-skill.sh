#!/usr/bin/env bash
set -euo pipefail

# Adopt a skill from an upstream skills repo into this plugin, and retire the
# upstream copy from the harness skill directories.
#
# Retiring is not optional: plugin skills are namespaced (kit:grilling) while
# harness-installed ones are not (grilling). Leaving both in place gives the
# model two near-identical descriptions to choose between, and the adopted
# version stops reliably winning.

usage() {
  cat >&2 <<'EOF'
usage: adopt-skill.sh <skill-name> [--force] [--keep-upstream] [--dry-run]

  --force          re-adopt a skill already present in this plugin (overwrites)
  --keep-upstream  do not remove the copy from the harness skill dirs
  --dry-run        print what would happen, change nothing

env:
  SKILLS_REPO  upstream checkout (default: ~/dev/mattpocock)
EOF
  exit 2
}

[ $# -ge 1 ] || usage

name=""
force=false
keep_upstream=false
dry_run=false

while [ $# -gt 0 ]; do
  case "$1" in
    --force)         force=true ;;
    --keep-upstream) keep_upstream=true ;;
    --dry-run)       dry_run=true ;;
    -h|--help)       usage ;;
    -*)              echo "error: unknown flag $1" >&2; usage ;;
    *)
      [ -z "$name" ] || { echo "error: only one skill name accepted" >&2; usage; }
      name="$1"
      ;;
  esac
  shift
done

[ -n "$name" ] || usage

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_ROOT="$PLUGIN_ROOT/plugins/kit/skills"
SKILLS_REPO="${SKILLS_REPO:-$HOME/dev/mattpocock}"
HARNESS_DIRS=("$HOME/.claude/skills" "$HOME/.agents/skills")

run() {
  if $dry_run; then
    echo "would: $*"
  else
    "$@"
  fi
}

[ -d "$SKILLS_REPO/skills" ] || {
  echo "error: no skills/ tree at $SKILLS_REPO — set SKILLS_REPO to the upstream checkout" >&2
  exit 1
}

# The upstream tree groups skills into category dirs (engineering/, productivity/,
# misc/, in-progress/) that get reshuffled over time, so locate by SKILL.md rather
# than assuming a path. deprecated/ is excluded — adopting a dead skill is a bug.
# Bash 3.2 is the only bash on stock macOS, so no mapfile/readarray here.
matches=""
match_count=0
while IFS= read -r dir; do
  matches="$matches$dir
"
  match_count=$((match_count + 1))
done < <(
  find "$SKILLS_REPO/skills" \
    -mindepth 2 -maxdepth 3 \
    -type d -name "$name" \
    -not -path '*/deprecated/*' \
    -not -path '*/node_modules/*' \
    -print | sort
)

case $match_count in
  0)
    echo "error: no skill named '$name' in $SKILLS_REPO/skills" >&2
    echo "hint: ls $SKILLS_REPO/skills/*/ | less" >&2
    exit 1
    ;;
  1) ;;
  *)
    echo "error: '$name' is ambiguous — matched $match_count directories:" >&2
    printf '%s' "$matches" | sed 's/^/  /' >&2
    exit 1
    ;;
esac

src="$(printf '%s' "$matches" | head -1)"
rel="${src#"$SKILLS_REPO"/}"

[ -f "$src/SKILL.md" ] || {
  echo "error: $src has no SKILL.md" >&2
  exit 1
}

dest="$DEST_ROOT/$name"
if [ -e "$dest" ] && ! $force; then
  echo "error: $dest already exists — pass --force to re-adopt (overwrites your edits)" >&2
  exit 1
fi

# A dirty or detached upstream makes the recorded SHA a lie, and the whole point
# of the sidecar is that `git diff <sha>..HEAD -- <path>` is trustworthy later.
sha="$(git -C "$SKILLS_REPO" rev-parse --short HEAD)"
upstream_repo="$(git -C "$SKILLS_REPO" config --get remote.origin.url 2>/dev/null || echo unknown)"
if ! git -C "$SKILLS_REPO" diff --quiet -- "$rel" || \
   ! git -C "$SKILLS_REPO" diff --cached --quiet -- "$rel"; then
  echo "warning: $rel has uncommitted changes in $SKILLS_REPO; recorded sha $sha will not match what was copied" >&2
fi

# Publishing this plugin redistributes every adopted skill, and the licenses worth
# adopting under all require their notice to travel with the copy. So a missing
# license is a stop, not a warning — it is the one mistake here that is hard to
# walk back once the repo is public.
license_src=""
for candidate in LICENSE LICENSE.md LICENSE.txt LICENCE COPYING; do
  if [ -f "$SKILLS_REPO/$candidate" ]; then
    license_src="$SKILLS_REPO/$candidate"
    break
  fi
done
[ -n "$license_src" ] || {
  echo "error: no license file at the root of $SKILLS_REPO" >&2
  echo "hint: confirm the upstream terms allow redistribution, then place its notice" >&2
  echo "      at $SKILLS_REPO/LICENSE so it can be carried alongside the skill" >&2
  exit 1
}

echo "adopting $name"
echo "  from $src"
echo "  at   $sha"

run rm -rf "$dest"
run mkdir -p "$DEST_ROOT"
run cp -R "$src" "$dest"

# A skill dir carrying its own license keeps it; the repo-root one is the fallback
# for the usual case where upstream licenses the whole tree once.
if [ -f "$src/LICENSE" ]; then
  echo "  license: kept the one that came with the skill"
else
  echo "  license: carrying $(basename "$license_src") from the upstream root"
  run cp "$license_src" "$dest/LICENSE"
fi

if $dry_run; then
  echo "would: write $dest/UPSTREAM"
else
  cat > "$dest/UPSTREAM" <<EOF
repo: $upstream_repo
path: $rel
sha: $sha

Forked at the sha above. To review what upstream changed since:
  git -C \$SKILLS_REPO diff $sha..HEAD -- $rel
Port what you want by hand, then bump the sha.

LICENSE beside this file is the upstream project's, carried here because its
terms require the notice to travel with the copy. It governs this directory
only; the rest of the plugin is under the LICENSE at the repo root.
EOF
fi

if $keep_upstream; then
  echo "  kept upstream copies (--keep-upstream) — expect duplicate skill triggers"
else
  for dir in "${HARNESS_DIRS[@]}"; do
    target="$dir/$name"
    [ -e "$target" ] || [ -L "$target" ] || continue
    echo "  retiring $target"
    run rm -rf "$target"
  done
fi

echo
echo "next: edit $dest/SKILL.md, then commit. Restart the session to load it as kit:$name."
