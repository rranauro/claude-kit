#!/usr/bin/env bash
set -euo pipefail

# Sync the plugin clone of the upstream skills repo and make every skill in it
# invocable only by its namespaced name (/mattpocock-skills:tdd), never picked
# by the model on its own.
#
# skillOverrides does not reach plugin skills, so the only lever is the
# disable-model-invocation frontmatter. It goes into a dedicated clone, never
# SKILLS_REPO itself: adopt-skill.sh copies from that checkout, and the flag
# would ride along into every fork.

usage() {
  cat >&2 <<'EOF'
usage: hide-plugin-skills.sh [--no-pull] [--dry-run]

  --no-pull  patch the clone as it stands; skip syncing from SKILLS_REPO
  --dry-run  print what would be hidden, change nothing

env:
  SKILLS_REPO  upstream checkout the clone pulls from (default: ~/dev/mattpocock)
  PLUGIN_DIR   the clone the marketplace is registered on
               (default: ~/.claude/local-marketplaces/mattpocock)
EOF
  exit 2
}

pull=true
dry_run=false

while [ $# -gt 0 ]; do
  case "$1" in
    --no-pull) pull=false ;;
    --dry-run) dry_run=true; pull=false ;;
    -h|--help) usage ;;
    *)         echo "error: unknown argument $1" >&2; usage ;;
  esac
  shift
done

SKILLS_REPO="${SKILLS_REPO:-$HOME/dev/mattpocock}"
PLUGIN_DIR="${PLUGIN_DIR:-$HOME/.claude/local-marketplaces/mattpocock}"

if [ ! -d "$PLUGIN_DIR/.git" ]; then
  $dry_run && { echo "would clone $SKILLS_REPO -> $PLUGIN_DIR"; exit 0; }
  mkdir -p "$(dirname "$PLUGIN_DIR")"
  git clone --quiet "$SKILLS_REPO" "$PLUGIN_DIR"
  echo "cloned $SKILLS_REPO -> $PLUGIN_DIR"
  echo "register it once: claude plugin marketplace add $PLUGIN_DIR && claude plugin install mattpocock-skills@mattpocock"
  pull=false
fi

if $pull; then
  # The only local edits in the clone are this script's own; drop them so the
  # fast-forward never conflicts, then put them back below.
  git -C "$PLUGIN_DIR" checkout --quiet -- .
  git -C "$PLUGIN_DIR" pull --quiet --ff-only
  echo "synced $PLUGIN_DIR to $(git -C "$PLUGIN_DIR" log -1 --format=%h)"
fi

changed=0
while IFS= read -r -d '' skill_md; do
  # Only the frontmatter block counts: a skill body that mentions the key in
  # prose must not read as already hidden.
  state="$(awk 'NR==1 && $0!="---" {print "nofm"; exit}
                NR==1 {next}
                $0=="---" {exit}
                /^disable-model-invocation:[[:space:]]*true[[:space:]]*$/ {print "true"; exit}
                /^disable-model-invocation:/ {print "other"; exit}' "$skill_md")"

  case "$state" in
    true) continue ;;
    nofm) echo "skip  ${skill_md#"$PLUGIN_DIR"/} (no frontmatter)" >&2; continue ;;
  esac

  echo "hide  ${skill_md#"$PLUGIN_DIR"/}"
  changed=$((changed + 1))
  $dry_run && continue

  tmp="$(mktemp)"
  awk -v state="$state" '
    NR==1 { print; if (state=="") print "disable-model-invocation: true"; next }
    !done && $0=="---" { done=1 }
    !done && /^disable-model-invocation:/ { print "disable-model-invocation: true"; next }
    { print }' "$skill_md" > "$tmp"
  cat "$tmp" > "$skill_md"
  rm -f "$tmp"
done < <(find "$PLUGIN_DIR/skills" -name SKILL.md -not -path '*/node_modules/*' -print0)

echo "$changed skill(s) $($dry_run && echo "would be hidden" || echo hidden) — new sessions pick it up"
