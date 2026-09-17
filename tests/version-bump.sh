#!/usr/bin/env bash
set -uo pipefail

# Every acceptance criterion on #152 is asserted here against a throwaway
# repository, because the check cannot be exercised by this repository's own
# PRs: it fires only on a diff that touches plugins/kit/**, and the PR that
# introduced it touches none of it. The test is the evidence, not a green run.
#
# The sandbox carries a real plugin manifest and a real branch cut, since both
# halves of the answer — did the payload move, and did the version move past the
# base — are read out of git rather than out of the CI event.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-version-bump.sh"
MANIFEST="plugins/kit/.claude-plugin/plugin.json"

passed=0
failed=0
current=""

# --- assertions ---------------------------------------------------------

ok()   { echo "  ok   $current — $1"; passed=$((passed + 1)); }
bad()  { echo "  FAIL $current — $1" >&2; failed=$((failed + 1)); }

assert_has() { # haystack needle label
  case "$1" in
    *"$2"*) ok "$3" ;;
    *)      bad "$3"; printf '       expected to find: %s\n' "$2" >&2
            printf '       in:\n%s\n' "$1" | sed 's/^/         /' >&2 ;;
  esac
}

# --- sandbox ------------------------------------------------------------

new_sandbox() {
  current="$1"
  echo "==> $current"
  # -P: mktemp hands back /var/... on macOS while git reports /private/var/...
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  MAIN="$SANDBOX/main"

  # `git init -b` is 2.28+; the default branch is named the long way round so
  # the sandbox builds on whatever git the runner ships.
  git init -q "$MAIN"
  git -C "$MAIN" symbolic-ref HEAD refs/heads/main
  git -C "$MAIN" config user.email test@example.com
  git -C "$MAIN" config user.name "Test"

  mkdir -p "$MAIN/$(dirname "$MANIFEST")" "$MAIN/plugins/kit/skills/demo" "$MAIN/docs"
  write_version 0.5.0
  echo "a skill" > "$MAIN/plugins/kit/skills/demo/SKILL.md"
  echo "a doc" > "$MAIN/docs/why.md"
  git -C "$MAIN" add -A
  git -C "$MAIN" commit -qm initial
}

end_sandbox() { rm -rf "$SANDBOX"; }

write_version() { # version
  printf '{\n  "name": "kit",\n  "version": "%s"\n}\n' "$1" > "$MAIN/$MANIFEST"
}

cut_branch() { git -C "$MAIN" checkout -q -b "$1"; }

commit() { git -C "$MAIN" add -A; git -C "$MAIN" commit -qm "$1"; }

# Runs the check the way CI does: from the repository root, naming the base
# branch. Prints combined output; sets `status`.
run_check() {
  out="$(cd "$MAIN" && "$SCRIPT" main 2>&1)"
  status=$?
}

assert_fails() { # label
  if [ "$status" -eq 0 ]; then bad "$1"; printf '%s\n' "$out" | sed 's/^/       /' >&2
  else ok "$1"; fi
}

assert_passes() { # label
  if [ "$status" -eq 0 ]; then ok "$1"
  else bad "$1"; printf '%s\n' "$out" | sed 's/^/       /' >&2; fi
}

# ========================================================================

new_sandbox "a payload change carrying the base version"
cut_branch 152-edit-a-skill
echo "an edited skill" > "$MAIN/plugins/kit/skills/demo/SKILL.md"
commit "edit a skill without bumping"
run_check
assert_fails "fails when the payload moved and the version did not"
assert_has "$out" "0.5.0" "and names the version it found"
end_sandbox

new_sandbox "a payload change that cuts a version"
cut_branch 152-edit-and-bump
echo "an edited skill" > "$MAIN/plugins/kit/skills/demo/SKILL.md"
write_version 0.6.0
commit "edit a skill and bump"
run_check
assert_passes "passes when the version moved past the base"
end_sandbox

new_sandbox "a change that touches no payload"
cut_branch 152-edit-a-doc
echo "an edited doc" > "$MAIN/docs/why.md"
commit "edit a doc"
run_check
assert_passes "passes without a bump when nothing under plugins/kit changed"
assert_has "$out" "plugins/kit" "and says why it had nothing to check"
end_sandbox

new_sandbox "a stale branch whose version trails the base"
cut_branch 152-stale
echo "an edited skill" > "$MAIN/plugins/kit/skills/demo/SKILL.md"
commit "edit a skill on a branch cut before the release"
git -C "$MAIN" checkout -q main
write_version 0.7.0
commit "cut 0.7.0 on main after the branch was cut"
git -C "$MAIN" checkout -q 152-stale
run_check
assert_fails "fails when the branch version is behind the base, not merely equal"
end_sandbox

new_sandbox "a branch whose only change is the version"
cut_branch 152-bump-only
write_version 0.6.0
commit "cut 0.6.0"
run_check
assert_passes "passes: the manifest is itself payload, and it moved"
end_sandbox

# --- summary ------------------------------------------------------------

echo
echo "version-bump: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
