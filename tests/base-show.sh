#!/usr/bin/env bash
set -uo pipefail

# Reading a file from the base branch through a tracked symlink, asserted against
# a scratch repository. The trap is the two ways a read can lie: `git show`
# calls a project's skill missing because its path crosses a link, and a read
# that resolved links itself could follow one out of the repository or into the
# pass's own branch. Git's verdict on the base tree is the only one allowed.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${BASE_SHOW_SCRIPT:-$ROOT/plugins/kit/scripts/base-show.sh}"

passed=0
failed=0
current=""

ok()  { echo "  ok   $current — $1"; passed=$((passed + 1)); }
bad() { echo "  FAIL $current — $1" >&2; failed=$((failed + 1)); }

assert_eq() { # actual expected label
  if [ "$1" = "$2" ]; then ok "$3"
  else bad "$3"; diff <(printf '%s\n' "$2") <(printf '%s\n' "$1") | sed 's/^/       /' >&2; fi
}

assert_has() { # haystack needle label
  case "$1" in
    *"$2"*) ok "$3" ;;
    *)      bad "$3"; printf '       expected to find: %s\n' "$2" >&2 ;;
  esac
}

# Runs the script in the scratch repo; sets code, stdout and stderr.
read_base() {
  stdout="$SANDBOX/stdout" stderr="$SANDBOX/stderr"
  (cd "$SANDBOX/repo" && "$SCRIPT" "$@") > "$stdout" 2> "$stderr"; code=$?
}

new_sandbox() {
  current="$1"
  echo "==> $current"
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  git init -q -b main "$SANDBOX/repo"
  git -C "$SANDBOX/repo" config user.name test
  git -C "$SANDBOX/repo" config user.email test@example.com
  git -C "$SANDBOX/repo" config commit.gpgsign false
}

# Commits everything and points origin/main at it, the way a fetch would.
land_on_base() {
  git -C "$SANDBOX/repo" add -A
  git -C "$SANDBOX/repo" commit -q -m "$1"
  git -C "$SANDBOX/repo" update-ref refs/remotes/origin/main HEAD
}

skill_body='---
name: pr-screenshots
---
Sign in first.'

new_sandbox "a real directory reads as it always did"
mkdir -p "$SANDBOX/repo/.claude/skills/pr-screenshots"
printf '%s\n' "$skill_body" > "$SANDBOX/repo/.claude/skills/pr-screenshots/SKILL.md"
land_on_base "real dir"
read_base origin/main .claude/skills/pr-screenshots/SKILL.md
assert_eq "$code" "0" "exits 0"
assert_eq "$(cat "$SANDBOX/stdout")" "$skill_body" "writes the blob to stdout"

new_sandbox "a symlinked skills directory is followed on the base branch"
mkdir -p "$SANDBOX/repo/skills/rx/skills/pr-screenshots" "$SANDBOX/repo/.claude"
printf '%s\n' "$skill_body" > "$SANDBOX/repo/skills/rx/skills/pr-screenshots/SKILL.md"
ln -s ../skills/rx/skills "$SANDBOX/repo/.claude/skills"
land_on_base "symlinked skills"
read_base origin/main .claude/skills/pr-screenshots/SKILL.md
assert_eq "$code" "0" "exits 0"
assert_eq "$(cat "$SANDBOX/stdout")" "$skill_body" "reads the skill through the link"
# The failure this exists to fix, stated so a regression names itself.
git -C "$SANDBOX/repo" show origin/main:.claude/skills/pr-screenshots/SKILL.md >/dev/null 2>&1; plain=$?
[ "$plain" -ne 0 ] && ok "plain git show cannot reach it" || bad "plain git show cannot reach it"

new_sandbox "a file the skill names is read through the link too"
mkdir -p "$SANDBOX/repo/skills/rx/skills/pr-screenshots/scripts" "$SANDBOX/repo/.claude"
printf '#!/bin/sh\necho captured\n' > "$SANDBOX/repo/skills/rx/skills/pr-screenshots/scripts/sign-in.sh"
ln -s ../skills/rx/skills "$SANDBOX/repo/.claude/skills"
land_on_base "named script"
read_base origin/main .claude/skills/pr-screenshots/scripts/sign-in.sh
assert_eq "$code" "0" "exits 0"
assert_eq "$(cat "$SANDBOX/stdout")" '#!/bin/sh
echo captured' "reads the named file"

new_sandbox "a link at the file itself is followed"
mkdir -p "$SANDBOX/repo/real"
printf 'rule\n' > "$SANDBOX/repo/real/CLAUDE.md"
ln -s real/CLAUDE.md "$SANDBOX/repo/CLAUDE.md"
land_on_base "file link"
read_base origin/main CLAUDE.md
assert_eq "$code" "0" "exits 0"
assert_eq "$(cat "$SANDBOX/stdout")" "rule" "reads the target"

new_sandbox "the bytes come back exact"
printf 'no trailing newline\n\n\n' > "$SANDBOX/repo/a.md"
printf 'no newline at all' > "$SANDBOX/repo/b.md"
printf 'nul\0inside\n' > "$SANDBOX/repo/c.bin"
land_on_base "bytes"
read_base origin/main a.md; cmp -s "$SANDBOX/stdout" "$SANDBOX/repo/a.md" && ok "trailing blank lines survive" || bad "trailing blank lines survive"
read_base origin/main b.md; cmp -s "$SANDBOX/stdout" "$SANDBOX/repo/b.md" && ok "a missing final newline is not added" || bad "a missing final newline is not added"
read_base origin/main c.bin; cmp -s "$SANDBOX/stdout" "$SANDBOX/repo/c.bin" && ok "a NUL byte survives" || bad "a NUL byte survives"

new_sandbox "an out file receives the blob and stdout stays empty"
mkdir -p "$SANDBOX/repo/skills/s" "$SANDBOX/repo/.claude"
printf '#!/bin/sh\necho hi\n' > "$SANDBOX/repo/skills/s/run.sh"
ln -s ../skills "$SANDBOX/repo/.claude/skills"
land_on_base "out file"
read_base origin/main .claude/skills/s/run.sh "$SANDBOX/copy.sh"
assert_eq "$code" "0" "exits 0"
cmp -s "$SANDBOX/copy.sh" "$SANDBOX/repo/skills/s/run.sh" && ok "the copy is the blob" || bad "the copy is the blob"
assert_eq "$(cat "$SANDBOX/stdout")" "" "stdout is empty"

new_sandbox "the pass's own branch cannot change what is read"
mkdir -p "$SANDBOX/repo/skills/base/pr-screenshots" "$SANDBOX/repo/skills/mine/pr-screenshots" "$SANDBOX/repo/.claude"
printf 'base version\n' > "$SANDBOX/repo/skills/base/pr-screenshots/SKILL.md"
printf 'branch version\n' > "$SANDBOX/repo/skills/mine/pr-screenshots/SKILL.md"
ln -s ../skills/base "$SANDBOX/repo/.claude/skills"
land_on_base "base"
git -C "$SANDBOX/repo" checkout -q -b 337-mine
rm "$SANDBOX/repo/.claude/skills"
ln -s ../skills/mine "$SANDBOX/repo/.claude/skills"
printf 'edited on branch\n' > "$SANDBOX/repo/skills/base/pr-screenshots/SKILL.md"
git -C "$SANDBOX/repo" add -A
git -C "$SANDBOX/repo" commit -q -m "retarget the link and edit the file"
read_base origin/main .claude/skills/pr-screenshots/SKILL.md
assert_eq "$(cat "$SANDBOX/stdout")" "base version" "the base's link and the base's file"
# Uncommitted edits in the working tree are the pass's too.
printf 'dirty\n' > "$SANDBOX/repo/skills/base/pr-screenshots/SKILL.md"
read_base origin/main .claude/skills/pr-screenshots/SKILL.md
assert_eq "$(cat "$SANDBOX/stdout")" "base version" "an unstaged edit changes nothing"

new_sandbox "a link out of the repository is missing, not followed"
mkdir -p "$SANDBOX/repo/.claude" "$SANDBOX/outside/pr-screenshots"
printf 'outside\n' > "$SANDBOX/outside/pr-screenshots/SKILL.md"
ln -s ../../outside "$SANDBOX/repo/.claude/skills"
land_on_base "escaping link"
read_base origin/main .claude/skills/pr-screenshots/SKILL.md
assert_eq "$code" "1" "exits 1"
assert_eq "$(cat "$SANDBOX/stdout")" "" "writes nothing"
assert_has "$(cat "$SANDBOX/stderr")" "missing: symlink .claude/skills/pr-screenshots/SKILL.md" "says what git said"

new_sandbox "a link to nothing is missing"
mkdir -p "$SANDBOX/repo/.claude"
ln -s ../skills/gone "$SANDBOX/repo/.claude/skills"
land_on_base "dangling link"
read_base origin/main .claude/skills/pr-screenshots/SKILL.md
assert_eq "$code" "1" "exits 1"
assert_has "$(cat "$SANDBOX/stderr")" "missing: dangling" "names the verdict"

new_sandbox "a link loop is missing"
mkdir -p "$SANDBOX/repo/.claude"
ln -s skills "$SANDBOX/repo/.claude/skills"
land_on_base "loop"
read_base origin/main .claude/skills/pr-screenshots/SKILL.md
assert_eq "$code" "1" "exits 1"
assert_has "$(cat "$SANDBOX/stderr")" "missing: loop" "names the verdict"

new_sandbox "an absent path is missing"
printf 'x\n' > "$SANDBOX/repo/a"
land_on_base "one file"
read_base origin/main .claude/skills/pr-screenshots/SKILL.md "$SANDBOX/copy"
assert_eq "$code" "1" "exits 1"
assert_has "$(cat "$SANDBOX/stderr")" "missing: missing .claude/skills/pr-screenshots/SKILL.md" "names the path"
[ ! -e "$SANDBOX/copy" ] && ok "no out file is left behind" || bad "no out file is left behind"

new_sandbox "a directory is not a blob"
mkdir -p "$SANDBOX/repo/skills/s"
printf 'x\n' > "$SANDBOX/repo/skills/s/a"
land_on_base "dir"
read_base origin/main skills/s
assert_eq "$code" "1" "exits 1"
assert_has "$(cat "$SANDBOX/stderr")" "missing: tree skills/s" "names the type"

new_sandbox "a path with spaces and a glob character reads and misses cleanly"
printf 'spaced\n' > "$SANDBOX/repo/my file.md"
land_on_base "spaces"
read_base origin/main "my file.md"
assert_eq "$(cat "$SANDBOX/stdout")" "spaced" "a spaced path is read"
read_base origin/main "no such *.md"
assert_eq "$code" "1" "a missing spaced glob path exits 1"
assert_has "$(cat "$SANDBOX/stderr")" "missing: missing no such *.md" "names the path unexpanded"

new_sandbox "a rev that does not exist is missing"
printf 'x\n' > "$SANDBOX/repo/a"
land_on_base "one file"
read_base origin/nope a
assert_eq "$code" "1" "exits 1"
assert_has "$(cat "$SANDBOX/stderr")" "missing:" "says so"

new_sandbox "wrong arguments are a usage error"
read_base origin/main
assert_eq "$code" "2" "exits 2 with no path"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
