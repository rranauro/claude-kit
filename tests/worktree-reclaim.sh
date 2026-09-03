#!/usr/bin/env bash
set -uo pipefail

# Every acceptance criterion on #73 is asserted here against a throwaway
# repository built from scratch, with `gh` stubbed on PATH so GitHub's answers
# are fixtures rather than network calls.
#
# The stub is the point rather than a convenience. The defect this ticket fixes
# is that a squash-merge and unpushed work produce an identical local refusal,
# so the only test that separates them asks the side that received the push —
# and a fixture is the only way to hold that answer still while asserting both.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/plugins/kit/scripts/worktree-reclaim.sh"
ORIG_PATH="$PATH"

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

assert_lacks() { # haystack needle label
  case "$1" in
    *"$2"*) bad "$3"; printf '       expected NOT to find: %s\n' "$2" >&2
            printf '       in:\n%s\n' "$1" | sed 's/^/         /' >&2 ;;
    *)      ok "$3" ;;
  esac
}

assert_missing_path() { # path label
  if [ -e "$1" ]; then bad "$2"; printf '       still on disk: %s\n' "$1" >&2
  else ok "$2"; fi
}

assert_present_path() { # path label
  if [ -e "$1" ]; then ok "$2"
  else bad "$2"; printf '       gone from disk: %s\n' "$1" >&2; fi
}

assert_branch_gone() { # branch label
  if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$1"
  then bad "$2"; printf '       branch still exists: %s\n' "$1" >&2
  else ok "$2"; fi
}

assert_branch_kept() { # branch label
  if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$1"
  then ok "$2"
  else bad "$2"; printf '       branch was deleted: %s\n' "$1" >&2; fi
}

# --- sandbox ------------------------------------------------------------

new_sandbox() {
  current="$1"
  echo "==> $current"
  # -P: mktemp hands back /var/... on macOS while git reports /private/var/...,
  # and every path assertion below compares the two.
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  MAIN="$SANDBOX/main"

  # `git init -b` is 2.28+; this repo has to build its sandbox on whatever git
  # the runner ships, so the default branch is named the long way round.
  git init -q --bare "$SANDBOX/remote.git"
  git -C "$SANDBOX/remote.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$SANDBOX/remote.git" "$MAIN" 2>/dev/null
  git -C "$MAIN" symbolic-ref HEAD refs/heads/main
  git -C "$MAIN" config user.email test@example.com
  git -C "$MAIN" config user.name "Test"

  mkdir -p "$MAIN/storage"
  echo x > "$MAIN/storage/.keep"
  echo hello > "$MAIN/README.md"
  git -C "$MAIN" add -A
  git -C "$MAIN" commit -qm initial
  git -C "$MAIN" push -q origin main
  mkdir -p "$MAIN/.claude/worktrees"

  GH_FIXTURES="$SANDBOX/fixtures"
  mkdir -p "$GH_FIXTURES" "$SANDBOX/bin"
  cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
# Answers `gh api repos/{owner}/{repo}/commits/<sha>/pulls` from a fixture
# keyed by the queried sha — that is what the real endpoint is keyed on,
# regardless of any branch name or headRefOid the fixture also carries.
if [ "$1" = "api" ]; then
  path="$2"
  sha="${path#*/commits/}"; sha="${sha%/pulls}"
  f="$GH_FIXTURES/$sha.json"
  if [ -f "$f" ]; then cat "$f"; exit 0; fi
  printf '{"message":"No commit found for SHA: %s","status":"422"}' "$sha"
  exit 1
fi
echo '[]'
GH
  chmod +x "$SANDBOX/bin/gh"
  export GH_FIXTURES
  export PATH="$SANDBOX/bin:$ORIG_PATH"
}

end_sandbox() {
  PATH="$ORIG_PATH"
  [ -n "${SANDBOX:-}" ] && chmod -R u+rwX "$SANDBOX" 2>/dev/null
  rm -rf "$SANDBOX"
}

# --- fixtures -----------------------------------------------------------

add_worktree() { # branch -> creates a worktree with one commit on top of main
  local branch="$1" wt="$MAIN/.claude/worktrees/$1"
  git -C "$MAIN" worktree add -q "$wt" -b "$branch" main
  echo "$branch" > "$wt/file.txt"
  git -C "$wt" add -A
  git -C "$wt" commit -qm "work on $branch"
}

push_branch() { git -C "$MAIN" push -q origin "$1"; }

# A PR fixture, keyed on the sha it answers for — the real endpoint is keyed on
# the commit, not the branch name. state is "open"/"closed" (the REST API's own
# spelling); merged_at is a quoted ISO timestamp or the literal null. An
# optional 5th arg sets headRefOid to something other than the queried sha, to
# prove the new accounting never reads it.
pr_fixture() { # sha number state merged_at [unrelated_head_ref_oid]
  local head="${5:-$1}"
  cat > "$GH_FIXTURES/$1.json" <<EOF
[{"number":$2,"state":"$3","merged_at":$4,"headRefOid":"$head","url":"https://example.test/pull/$2"}]
EOF
}

tip() { git -C "$MAIN" rev-parse "refs/heads/$1"; }

# The two leftovers `kit:start-ticket` wire-worktree creates, and the deletion
# the second one causes for the worktree's whole life.
wire_setup_artifacts() { # branch
  local wt="$MAIN/.claude/worktrees/$1"
  ln -s "$MAIN/README.md" "$wt/credentials.local"   # untracked symlink
  rm -rf "$wt/storage"
  ln -s "$MAIN/storage" "$wt/storage"               # symlink over a tracked dir
}

# A cache directory whose writer left it non-traversable, which is what defeats
# a bare `rm -rf` and leaves the husk the sweep existed to remove.
leave_unreadable_husk() { # branch
  local wt="$MAIN/.claude/worktrees/$1"
  mkdir -p "$wt/tmp/cache/bootsnap"
  echo junk > "$wt/tmp/cache/bootsnap/data"
  chmod 000 "$wt/tmp/cache/bootsnap"
}

run() { # args... -> runs the script against $MAIN with stdin closed
  "$SCRIPT" --repo "$MAIN" \
            --worktree-root "$MAIN/.claude/worktrees" "$@" </dev/null 2>&1
}

# ========================================================================
# AC1 · A named target and a sweep reclaim by the same rules, with the same
#       treatment of setup-artifact leftovers and non-traversable husks.
# ========================================================================

new_sandbox "AC1 target and sweep agree"
add_worktree alpha
push_branch alpha
pr_fixture "$(tip alpha)" 11 closed '"2024-01-01T00:00:00Z"'
wire_setup_artifacts alpha
add_worktree beta
push_branch beta
pr_fixture "$(tip beta)" 12 closed '"2024-01-01T00:00:00Z"'
wire_setup_artifacts beta

# The same worktree, reached both ways. Identical lines is the assertion — a
# weaker one would not catch the two paths drifting apart, which is the defect.
sweep_verdict="$(run | grep '^verdict	beta	')"
target_verdict="$(run --target beta | grep '^verdict	beta	')"
if [ "$sweep_verdict" = "$target_verdict" ]; then ok "same verdict from a sweep and a named target"
else bad "same verdict from a sweep and a named target"
     printf '       sweep:  %s\n       target: %s\n' "$sweep_verdict" "$target_verdict" >&2; fi

assert_has "$sweep_verdict" "reclaim" "setup-artifact leftovers do not read as work"
assert_lacks "$sweep_verdict" "hold" "a symlink over a tracked dir is not uncommitted work"

# A named target touches only its target.
run --target beta --act >/dev/null
assert_missing_path "$MAIN/.claude/worktrees/beta" "a named target is reclaimed"
assert_present_path "$MAIN/.claude/worktrees/alpha" "a named target leaves every other worktree alone"
end_sandbox

new_sandbox "AC1 husk sweep"
add_worktree alpha
push_branch alpha
pr_fixture "$(tip alpha)" 11 closed '"2024-01-01T00:00:00Z"'
leave_unreadable_husk alpha
# A husk git no longer names, left non-traversable by whatever wrote it. This is
# the case a bare `rm -rf` fails on — it cannot descend into the directory to
# delete what is under it, so it aborts on the directory itself and leaves the
# husk the sweep existed to remove.
mkdir -p "$MAIN/.claude/worktrees/999-husk/tmp/cache"
echo junk > "$MAIN/.claude/worktrees/999-husk/tmp/cache/data"
chmod 000 "$MAIN/.claude/worktrees/999-husk/tmp/cache"
out="$(run --act)"
assert_missing_path "$MAIN/.claude/worktrees/alpha" "a non-traversable cache does not survive removal"
assert_missing_path "$MAIN/.claude/worktrees/999-husk" "nor does a non-traversable husk survive the sweep"
assert_has "$out" "swept	$MAIN/.claude/worktrees/999-husk" "the sweep is reported"
end_sandbox

# ========================================================================
# AC2 · A branch is deleted only where GitHub accounts for its tip,
#       established by asking rather than inferred from a refusal.
# ========================================================================

new_sandbox "AC2 squash-merge, tip accounted"
add_worktree alpha
# Deliberately NOT pushed to any remote ref, and main has moved on with an
# unrelated commit — exactly the shape a squash-merge leaves behind. Every
# local test (`git branch -d`, `rev-list --not --remotes`) reads this as
# unmerged. The fixture is keyed on the branch's own tip — what the new code
# actually queries — and carries a headRefOid that DIFFERS from it (#98): the
# accounting must reach the right answer without ever reading that field.
pr_fixture "$(tip alpha)" 11 closed '"2024-01-01T00:00:00Z"' \
  "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
out="$(run --act)"
assert_branch_gone alpha "a squash-merged branch is deleted on GitHub's answer"
assert_has "$out" "branch-deleted	alpha" "the deletion is reported"
end_sandbox

new_sandbox "AC2 closed PR counts"
add_worktree alpha
pr_fixture "$(tip alpha)" 11 closed null
run --act >/dev/null
assert_branch_gone alpha "a closed, unmerged PR whose commit GitHub has still accounts for it"
end_sandbox

new_sandbox "AC2 open PR does not count"
add_worktree alpha
push_branch alpha
pr_fixture "$(tip alpha)" 11 open null
run --act >/dev/null
assert_branch_kept alpha "an open PR is not a terminal state, so the branch stays"
end_sandbox

# ========================================================================
# AC3 · A branch holding commits the remote has never received is never
#       deleted, whatever its PR state, and is reported.
# ========================================================================

new_sandbox "AC3 unpushed commits above a merged PR"
add_worktree alpha
received="$(tip alpha)"
echo more > "$MAIN/.claude/worktrees/alpha/extra.txt"
git -C "$MAIN/.claude/worktrees/alpha" add -A
git -C "$MAIN/.claude/worktrees/alpha" commit -qm "committed but never pushed"
# GitHub received the earlier tip, not this one — the fixture is keyed on
# $received, so a lookup by the current (moved-on) tip finds nothing. Locally
# this is the identical refusal a squash-merge produces; the two are now
# separated by asking about the exact commit at HEAD, not by comparing oids.
pr_fixture "$received" 11 closed '"2024-01-01T00:00:00Z"'
out="$(run --act)"
assert_branch_kept alpha "commits GitHub never received are not destroyed"
assert_has "$out" "branch-kept	alpha" "the kept branch is reported so it cannot accumulate unseen"
assert_lacks "$out" "ahead of" "the reason never claims an ahead/behind relationship the run did not test"
end_sandbox

new_sandbox "AC3 unpushed commits with no PR at all"
add_worktree alpha
out="$(run --act)"
assert_branch_kept alpha "a never-pushed branch with no PR keeps its commits"
assert_has "$out" "branch-kept	alpha" "and is reported"
end_sandbox

new_sandbox "AC3 GitHub unreachable fails safe"
add_worktree alpha
cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "error connecting to api.github.com" >&2
exit 1
GH
chmod +x "$SANDBOX/bin/gh"
out="$(run --act)"
assert_branch_kept alpha "an unanswered question is not an accounted tip"
assert_has "$out" "branch-kept	alpha" "and the reason is reported"
end_sandbox

# ========================================================================
# AC4 · A worktree whose branch never had a pull request is reclaimed.
# ========================================================================

new_sandbox "AC4 no PR ever"
add_worktree alpha
out="$(run --act)"
assert_missing_path "$MAIN/.claude/worktrees/alpha" "the directory is reclaimed without a PR"
assert_branch_kept alpha "while its unaccounted branch survives"
assert_has "$out" "removed	" "the removal is reported"
end_sandbox

new_sandbox "AC4 no PR but the tip is on a remote ref"
add_worktree alpha
push_branch alpha
run --act >/dev/null
assert_missing_path "$MAIN/.claude/worktrees/alpha" "the directory is reclaimed"
assert_branch_gone alpha "a tip present on a remote ref accounts for the branch"
end_sandbox

# ========================================================================
# AC5 · A worktree someone is working in is never removed, and the skip is
#       reported with its reason.
# ========================================================================

new_sandbox "AC5 uncommitted work is never eaten"
add_worktree alpha
push_branch alpha
pr_fixture "$(tip alpha)" 11 closed '"2024-01-01T00:00:00Z"'
echo "half-finished" >> "$MAIN/.claude/worktrees/alpha/file.txt"
echo "scratch" > "$MAIN/.claude/worktrees/alpha/notes.md"
out="$(run --act)"
assert_present_path "$MAIN/.claude/worktrees/alpha" "a dirty worktree is left alone"
assert_branch_kept alpha "and its branch is left alone with it"
assert_has "$out" "held	" "the skip is reported"
assert_has "$out" "uncommitted" "the skip carries its reason"
end_sandbox

new_sandbox "AC5 a locked worktree is busy"
add_worktree alpha
push_branch alpha
pr_fixture "$(tip alpha)" 11 closed '"2024-01-01T00:00:00Z"'
git -C "$MAIN" worktree lock --reason "running the app" "$MAIN/.claude/worktrees/alpha"
out="$(run --act)"
assert_present_path "$MAIN/.claude/worktrees/alpha" "a locked worktree is left alone"
assert_has "$out" "held	" "the skip is reported"
end_sandbox

# ========================================================================
# AC6 · Running unattended asks nothing and still reports every removal and
#       every skip.
# ========================================================================

new_sandbox "AC6 unattended reports everything"
add_worktree alpha; push_branch alpha
pr_fixture "$(tip alpha)" 11 closed '"2024-01-01T00:00:00Z"'
add_worktree beta;  push_branch beta
pr_fixture "$(tip beta)" 12 open null
add_worktree gamma
echo dirty > "$MAIN/.claude/worktrees/gamma/dirty.txt"
# stdin is closed by `run`, so a prompt would fail rather than hang.
out="$(run --act)"
assert_has "$out" "removed	$MAIN/.claude/worktrees/alpha" "the reclaimed worktree is reported"
assert_has "$out" "branch-deleted	alpha" "the deleted branch is reported"
assert_has "$out" "removed	$MAIN/.claude/worktrees/beta" "an open PR still frees its directory"
assert_has "$out" "branch-kept	beta" "and its branch is reported as kept"
assert_has "$out" "held	$MAIN/.claude/worktrees/gamma" "the dirty worktree is reported as held"
end_sandbox

new_sandbox "AC6 orphan husks are swept"
add_worktree alpha
push_branch alpha
pr_fixture "$(tip alpha)" 11 closed '"2024-01-01T00:00:00Z"'
# A husk from a previous run: a directory git no longer names.
mkdir -p "$MAIN/.claude/worktrees/999-orphan/tmp"
echo junk > "$MAIN/.claude/worktrees/999-orphan/tmp/x"
out="$(run --act)"
assert_missing_path "$MAIN/.claude/worktrees/999-orphan" "a husk git does not name is swept"
assert_has "$out" "orphan	$MAIN/.claude/worktrees/999-orphan" "the orphan is reported"
end_sandbox

new_sandbox "AC6 without a declared root, no directory is ever listed"
add_worktree alpha
push_branch alpha
pr_fixture "$(tip alpha)" 11 closed '"2024-01-01T00:00:00Z"'
mkdir -p "$MAIN/.claude/worktrees/someone-elses-repo"
echo precious > "$MAIN/.claude/worktrees/someone-elses-repo/data"
out="$("$SCRIPT" --repo "$MAIN" --act </dev/null 2>&1)"
assert_present_path "$MAIN/.claude/worktrees/someone-elses-repo" \
  "an undeclared root leaves unlisted directories untouched"
assert_lacks "$out" "orphan	" "and proposes no orphans it cannot vouch for"
end_sandbox

# ========================================================================
# AC7 · Where a project owns worktree teardown, its own remove command runs
#       instead of a raw `git worktree remove`.
# ========================================================================

new_sandbox "AC7 the project's remove command is used"
add_worktree alpha
push_branch alpha
pr_fixture "$(tip alpha)" 11 closed '"2024-01-01T00:00:00Z"'
cat > "$SANDBOX/bin/project-remove" <<GH
#!/usr/bin/env bash
echo "\$@" > "$SANDBOX/remove-was-called"
git -C "$MAIN" worktree remove --force "\$2"
GH
chmod +x "$SANDBOX/bin/project-remove"
"$SCRIPT" --repo "$MAIN" --remove-cmd project-remove --act </dev/null >/dev/null 2>&1
assert_present_path "$SANDBOX/remove-was-called" "the project's remove command ran"
assert_has "$(cat "$SANDBOX/remove-was-called" 2>/dev/null || echo)" "alpha" \
  "and was handed the branch"
assert_missing_path "$MAIN/.claude/worktrees/alpha" "the worktree is gone"
end_sandbox

# ========================================================================
# AC2/AC3 · The same test, reachable by any other caller that deletes a
#           branch, so no caller carries its own copy of the escalation.
# ========================================================================

new_sandbox "the accounting seam other callers use"
add_worktree alpha
received="$(tip alpha)"
pr_fixture "$received" 11 closed '"2024-01-01T00:00:00Z"'
if "$SCRIPT" --repo "$MAIN" --account alpha >/dev/null 2>&1
then ok "--account exits 0 when GitHub has the tip"
else bad "--account exits 0 when GitHub has the tip"; fi

echo more > "$MAIN/.claude/worktrees/alpha/extra.txt"
git -C "$MAIN/.claude/worktrees/alpha" add -A
git -C "$MAIN/.claude/worktrees/alpha" commit -qm "never pushed"
out="$("$SCRIPT" --repo "$MAIN" --account alpha 2>&1)"
if [ $? -eq 0 ]
then bad "--account exits non-zero once the tip moves past the PR"
else ok "--account exits non-zero once the tip moves past the PR"; fi
assert_has "$out" "unaccounted	alpha" "and says so on stdout"
end_sandbox

# --- summary ------------------------------------------------------------

echo
echo "worktree-reclaim: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
