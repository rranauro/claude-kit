#!/usr/bin/env bash
set -uo pipefail

# Where a review lands, asserted against throwaway repositories with `gh` and
# `claude` stubbed on PATH. What the review says is not under test.
#
# Every case runs from the main checkout, as /kit:start-review does. That is the
# trap: the local diff there is empty, so a script that places the review from it
# puts every monorepo review at the root — and only a run from main shows it.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PR_REVIEW_SCRIPT:-$ROOT/plugins/kit/scripts/pr-review.sh}"
ORIG_PATH="$PATH"
ORIG_HOME="$HOME"

passed=0
failed=0
current=""

# --- assertions ---------------------------------------------------------

ok()  { echo "  ok   $current — $1"; passed=$((passed + 1)); }
bad() { echo "  FAIL $current — $1" >&2; failed=$((failed + 1)); }

assert_has() { # haystack needle label
  case "$1" in
    *"$2"*) ok "$3" ;;
    *)      bad "$3"; printf '       expected to find: %s\n' "$2" >&2
            printf '       in:\n%s\n' "$1" | sed 's/^/         /' >&2 ;;
  esac
}

assert_file() { # path label
  if [ -f "$1" ]; then ok "$2"
  else bad "$2"; printf '       no file at %s\n' "$1" >&2; fi
}

# --- sandbox ------------------------------------------------------------

new_sandbox() {
  current="$1"
  echo "==> $current"
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  MAIN="$SANDBOX/repo"
  mkdir -p "$SANDBOX/bin" "$SANDBOX/home" "$MAIN"

  # The PR's file list is the fixture the placement is decided from; the author
  # is somebody else, so the script takes its file-writing side.
  cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$*" in
  "repo view"*)         echo "owner/repo" ;;
  "api user"*)          echo "me" ;;
  *"--json author"*)    echo "colleague"; echo "2 files changed, +5 -1"; cat "$PR_FILES" ;;
esac
exit 0
GH
  cat > "$SANDBOX/bin/claude" <<'CLAUDE'
#!/usr/bin/env bash
printf '<!-- claude-pr-review -->\n## Automated review\nfine\n'
CLAUDE
  chmod +x "$SANDBOX/bin/gh" "$SANDBOX/bin/claude"
  export PR_FILES="$SANDBOX/pr-files"
  export PATH="$SANDBOX/bin:$ORIG_PATH"
  export HOME="$SANDBOX/home"

  git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email t@example.com
  git -C "$MAIN" config user.name test
}

commit() { git -C "$MAIN" add -A && git -C "$MAIN" commit -qm fixture; }
pr_files() { printf '%s\n' "$@" > "$PR_FILES"; }
review() { OUT="$(cd "${RUN_FROM:-$MAIN}" && "$SCRIPT" "$@" 7 2>&1)"; }

end_sandbox() {
  PATH="$ORIG_PATH"
  HOME="$ORIG_HOME"
  unset RUN_FROM
  rm -rf "$SANDBOX"
}

# --- single app ---------------------------------------------------------

new_sandbox "a single app lands at its root"
touch "$MAIN/Gemfile"; echo "/tmp" > "$MAIN/.gitignore"; commit
pr_files app/models/user.rb
review
assert_file "$MAIN/tmp/reviews/pr-7/claude-review.md" "written under the root's tmp/reviews"
assert_has "$OUT" "$MAIN/tmp/reviews/pr-7/claude-review.md" "prints the path it wrote"
end_sandbox

# --- monorepo -----------------------------------------------------------

new_sandbox "a monorepo review lands under the project the PR changes"
mkdir -p "$MAIN/rx"; touch "$MAIN/rx/Gemfile"; echo "tmp/" > "$MAIN/.gitignore"; commit
pr_files rx/app/models/user.rb rx/app/views/users/show.html.erb
review
assert_file "$MAIN/rx/tmp/reviews/pr-7/claude-review.md" "written under rx/, though main's diff is empty"
end_sandbox

new_sandbox "a review run from a linked worktree still lands in the main checkout"
mkdir -p "$MAIN/rx"; touch "$MAIN/rx/Gemfile"; echo "tmp/" > "$MAIN/.gitignore"; commit
git -C "$MAIN" worktree add -q "$SANDBOX/wt" -b review-7
pr_files rx/app/models/user.rb
RUN_FROM="$SANDBOX/wt" review
assert_file "$MAIN/rx/tmp/reviews/pr-7/claude-review.md" "written in the main checkout"
end_sandbox

# --- declared Location --------------------------------------------------

new_sandbox "a declared Location is honoured"
touch "$MAIN/Gemfile"
printf '## Visual PR and review output\n- Format: markdown\n- Location: reviews/pr-<n>/\n' > "$MAIN/CLAUDE.md"
commit
pr_files app/models/user.rb
review
assert_file "$MAIN/reviews/pr-7/claude-review.md" "written to the declared Location with <n> filled"
end_sandbox

new_sandbox "a declared Location resolves inside the monorepo project"
mkdir -p "$MAIN/rx"; touch "$MAIN/rx/Gemfile"
printf '## Visual PR and review output\n- Location: tmp/reviews/pr-<n>/\n' > "$MAIN/CLAUDE.md"
commit
pr_files rx/app/models/user.rb
review
assert_file "$MAIN/rx/tmp/reviews/pr-7/claude-review.md" "relative to the project, not the root"
end_sandbox

new_sandbox "the nearer rules file wins, and CLAUDE.local.md wins beside it"
mkdir -p "$MAIN/rx"; touch "$MAIN/rx/Gemfile"
printf '## Visual PR and review output\n- Location: root-wide/pr-<n>/\n' > "$MAIN/CLAUDE.md"
printf '## Visual PR and review output\n- Location: project-wide/pr-<n>/\n' > "$MAIN/rx/CLAUDE.md"
commit
printf '## Visual PR and review output\n- Location: mine/pr-<n>/\n' > "$MAIN/rx/CLAUDE.local.md"
pr_files rx/app/models/user.rb
review
assert_file "$MAIN/rx/mine/pr-7/claude-review.md" "the sub-project's CLAUDE.local.md decided it"
end_sandbox

new_sandbox "the rules come from the nearest CLAUDE.md, wherever the build marker is"
mkdir -p "$MAIN/rx/engines/billing"; touch "$MAIN/rx/engines/billing/Gemfile"
printf '## Visual PR and review output\n- Location: from-rx/pr-<n>/\n' > "$MAIN/rx/CLAUDE.md"
commit
pr_files rx/engines/billing/lib/invoice.rb
review
assert_file "$MAIN/rx/engines/billing/from-rx/pr-7/claude-review.md" "rx/CLAUDE.md applied above the engine"
end_sandbox

new_sandbox "the logged size is the PR's, not the empty local diff"
touch "$MAIN/Gemfile"; echo "/tmp" > "$MAIN/.gitignore"; commit
pr_files app/models/user.rb
review
assert_has "$(cat "$HOME"/.claude/logs/pr-review/*.log)" "changed=[2 files changed, +5 -1]" "the log carries the PR's size"
end_sandbox

# --- detached -----------------------------------------------------------

new_sandbox "a detached launch names the file it will write"
touch "$MAIN/Gemfile"; echo "/tmp" > "$MAIN/.gitignore"; commit
pr_files app/models/user.rb
review --detach
assert_has "$OUT" "writing to: $MAIN/tmp/reviews/pr-7/claude-review.md" "the launch line carries the path"
end_sandbox

# --- summary ------------------------------------------------------------

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
