#!/usr/bin/env bash
set -euo pipefail

# Everything here is a check that a drive-by PR can fail without anyone noticing
# by reading the diff: a shell script that no longer parses, a manifest that is
# no longer JSON, a skill or subagent whose frontmatter stops matching its file
# — all of which fail at load time in the harness rather than at review time — a
# plugin version that would stop installs from updating at all, a piece that
# would leave the kit without saying who wrote it, a vendored skill that dropped
# the notice its licence requires, and an inline skill whose model pin would
# outlive it.
#
# Shape only, and it stays under a second so it is worth running before every
# push. Behaviour is asserted in tests/, which CI runs as its own step.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failed=0
this_failed=0
fail() {
  echo "  FAIL: $*" >&2
  failed=1
  this_failed=1
}

frontmatter_value() {
  awk -v k="$2" 'NR>1 && /^---$/{exit} $0 ~ "^"k":" {sub("^"k":[[:space:]]*",""); print; exit}' "$1"
}

# Frontmatter that does not open on line 1 is read as body text. Unclosed, the
# whole body is frontmatter, and a key written anywhere in it would satisfy
# every check that reads one.
check_fences() {
  [ "$(head -1 "$1")" = "---" ] || { fail "$1 does not open with ---"; return 1; }
  awk 'NR>1 && /^---$/{f=1; exit} END{exit !f}' "$1" ||
    { fail "$1 never closes its frontmatter with ---"; return 1; }
}

# A skill and a subagent fail the same way, at load and with nothing said: a
# file with no name or description is dropped. A name that differs from where
# the file lives answers to something other than what its path advertises.
check_frontmatter() {
  local md="$1" expected="$2" name desc
  check_fences "$md" || return 1

  name="$(frontmatter_value "$md" name)"
  desc="$(frontmatter_value "$md" description)"

  [ -n "$name" ] || fail "$md has no name in its frontmatter"
  [ -n "$desc" ] || fail "$md has no description in its frontmatter"
  if [ -n "$name" ] && [ "$name" != "$expected" ]; then
    fail "$md declares name '$name' but lives at '$expected'"
  fi
}

# docs/companion-skills.md#every-piece-names-its-author has why, and the line.
KIT_LICENSE='MIT — Copyright (c) 2026 Ron Ranauro, https://github.com/rranauro/claude-kit'

check_kit_license() {
  [ "$(frontmatter_value "$1" license)" = "$KIT_LICENSE" ] ||
    fail "$1 does not carry the kit's license: line — see docs/companion-skills.md#every-piece-names-its-author"
}

# A vendored line names each ancestor's notice file as `(LICENSE…)`. Checking
# both directions, and the count against the credits, is what fails a dropped
# ancestor rather than only a dropped LICENSE.
check_vendored_license() {
  local skill="$1" md="$1/SKILL.md" license n cited credits notices=0
  license="$(frontmatter_value "$md" license)"
  [ -n "$license" ] || {
    fail "$md is vendored but names no license: in its frontmatter — see docs/companion-skills.md#vendoring"
    return
  }
  # An unchanged fork claims nothing, so only a claim that is there is checked.
  case "$license" in
    *"; changes "*)
      [ "${license##*; changes }" = "${KIT_LICENSE#MIT — }" ] ||
        fail "$md's license: credits its changes in words other than the kit's own line" ;;
  esac
  for n in "$skill"/LICENSE "$skill"/LICENSE-*; do
    [ -f "$n" ] || continue
    notices=$((notices + 1))
    case "$license" in
      *"(${n##*/})"*) ;;
      *) fail "$md's license: does not credit the ancestor in ${n##*/}" ;;
    esac
  done
  while IFS= read -r cited; do
    [ -f "$skill/$cited" ] || fail "$md's license: cites $cited, which $skill does not carry"
  done < <(printf '%s\n' "$license" | grep -o '(LICENSE[^)]*)' | tr -d '()')
  credits="$(awk 'NR>1 && /^---$/{exit} /^[[:space:]]+- skill:/{c++} END{print c+0}' "$md")"
  [ "$notices" -ge "$credits" ] ||
    fail "$md credits $credits upstreams but $skill carries $notices notice files"
}

echo "==> shell syntax"
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then
    echo "  ok   $f"
  else
    fail "$f does not parse"
    bash -n "$f" || true
  fi
done < <(find . -path ./.git -prune -o -name '*.sh' -print | sort)

echo "==> json manifests"
while IFS= read -r f; do
  # python3 over jq: it ships on macOS and every GitHub runner, jq does not.
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null; then
    echo "  ok   $f"
  else
    fail "$f is not valid JSON"
  fi
done < <(find . -path ./.git -prune -o -name '*.json' -print | sort)

echo "==> plugin versioning"
# A version anywhere pins installs to it until someone raises it; with none, an
# install tracks the commit. ADR 0006 has why.
rc=0
python3 - <<'PY' || rc=$?
import json, sys
try:
    plugin = json.load(open("plugins/kit/.claude-plugin/plugin.json"))
    market = json.load(open(".claude-plugin/marketplace.json"))
except (OSError, ValueError):
    sys.exit(2)  # the json manifests check already names the cause
entries = [p for p in market.get("plugins", []) if p.get("name") == plugin.get("name")]
sys.exit(1 if "version" in plugin or any("version" in p for p in entries) else 0)
PY
case "$rc" in
  0) echo "  ok   kit declares no version" ;;
  2) echo "  skip a manifest is unreadable" ;;
  *) fail "kit declares a version in plugin.json or marketplace.json; the commit is its version" ;;
esac

echo "==> skill frontmatter"
for skill in plugins/kit/skills/*/; do
  [ -d "$skill" ] || continue
  skill="${skill%/}"
  dir_name="$(basename "$skill")"
  md="$skill/SKILL.md"
  this_failed=0

  [ -f "$md" ] || { fail "$skill has no SKILL.md"; continue; }

  check_frontmatter "$md" "$dir_name" || continue

  # A skill's model or effort override lasts for the rest of the turn, not the
  # rest of the skill, so an inline skill that names one carries its caller onto
  # it. Only one that runs isolated may. docs/commands.md has the rule.
  if awk 'NR>1 && /^---$/{exit} /^(model|effort):/{f=1; exit} END{exit !f}' "$md" &&
     ! awk 'NR>1 && /^---$/{exit} /^context:[[:space:]]*fork[[:space:]]*$/{f=1; exit} END{exit !f}' "$md"; then
    fail "$md names a model or effort but runs inline — only a forked skill may; see docs/commands.md#only-work-that-starts-its-own-turn-names-a-model"
  fi

  # A hand-copied skill passes every check above while dropping the notice its
  # licence requires to travel with it, and drops out of the one list that
  # answers "what is not ours?". A sidecar or a credits block is the skill
  # saying it came from elsewhere, so both halves are checkable from there.
  if [ -f "$skill/UPSTREAM" ] || awk 'NR>1 && /^---$/{exit} /^[[:space:]]+credits:/{f=1; exit} END{exit !f}' "$md"; then
    [ -f "$skill/LICENSE" ] ||
      fail "$skill credits an upstream but carries no LICENSE — see docs/companion-skills.md#vendoring"
    grep -q "^| \`$dir_name\` |" docs/companion-skills.md ||
      fail "$skill credits an upstream but has no row in docs/companion-skills.md#what-is-vendored"
    check_vendored_license "$skill"
  else
    check_kit_license "$md"
  fi

  [ "$this_failed" -eq 1 ] || echo "  ok   $md"
done

echo "==> agent frontmatter"
for md in plugins/kit/agents/*.md; do
  [ -f "$md" ] || continue
  this_failed=0
  check_frontmatter "$md" "$(basename "$md" .md)" || continue
  check_kit_license "$md"
  [ "$this_failed" -eq 1 ] || echo "  ok   $md"
done

echo "==> command frontmatter"
for md in plugins/kit/commands/*.md; do
  [ -f "$md" ] || continue
  this_failed=0
  check_fences "$md" || continue
  check_kit_license "$md"
  [ "$this_failed" -eq 1 ] || echo "  ok   $md"
done

echo
if [ "$failed" -eq 0 ]; then
  echo "all checks passed"
else
  echo "checks failed" >&2
fi
exit "$failed"
