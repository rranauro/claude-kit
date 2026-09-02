#!/usr/bin/env bash
set -euo pipefail

# Everything here is a check that a drive-by PR can fail without anyone noticing
# by reading the diff: a shell script that no longer parses, a manifest that is
# no longer JSON, a skill whose frontmatter stops matching its directory. All
# three fail at load time in the harness rather than at review time.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failed=0
this_failed=0
fail() {
  echo "  FAIL: $*" >&2
  failed=1
  this_failed=1
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

echo "==> skill frontmatter"
for skill in plugins/kit/skills/*/; do
  [ -d "$skill" ] || continue
  skill="${skill%/}"
  dir_name="$(basename "$skill")"
  md="$skill/SKILL.md"
  this_failed=0

  [ -f "$md" ] || { fail "$skill has no SKILL.md"; continue; }

  # Frontmatter has to open on line 1; a leading blank line makes the harness
  # read the whole block as body text and the skill silently never triggers.
  [ "$(head -1 "$md")" = "---" ] || { fail "$md does not open with ---"; continue; }

  name="$(awk 'NR>1 && /^---$/{exit} /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$md")"
  desc="$(awk 'NR>1 && /^---$/{exit} /^description:/{print; exit}' "$md")"

  [ -n "$name" ] || fail "$md has no name in its frontmatter"
  [ -n "$desc" ] || fail "$md has no description in its frontmatter"

  # The invocable name comes from the directory, so a mismatch means the skill
  # answers to something other than what its own frontmatter advertises.
  if [ -n "$name" ] && [ "$name" != "$dir_name" ]; then
    fail "$md declares name '$name' but lives in '$dir_name'"
  fi

  [ "$this_failed" -eq 1 ] || echo "  ok   $md"
done

echo "==> worktree-reclaim behaviour"
# Builds a throwaway repository per case with `gh` stubbed on PATH. It is the
# only check here that asserts behavior rather than shape, because the branch
# test it covers is one where reading the code cannot tell you whether it is
# right — a squash-merge and unpushed work look identical until something asks.
if bash tests/worktree-reclaim.sh > /tmp/worktree-reclaim-lint.$$ 2>&1; then
  echo "  ok   $(tail -1 /tmp/worktree-reclaim-lint.$$)"
else
  fail "tests/worktree-reclaim.sh"
  cat /tmp/worktree-reclaim-lint.$$ >&2
fi
rm -f /tmp/worktree-reclaim-lint.$$

echo
if [ "$failed" -eq 0 ]; then
  echo "all checks passed"
else
  echo "checks failed" >&2
fi
exit "$failed"
