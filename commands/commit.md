Create a git commit for the current changes.

**Step 1 — Situational awareness (run in parallel):**
- `git status` — see all modified and untracked files (never use -uall)
- `git diff HEAD` — see all staged and unstaged changes
- `git log --oneline -10` — see recent commit message style and conventions
- `git branch --show-current` — confirm we are NOT on main or master
- `git diff main...HEAD --stat` — see file-level summary of all changes vs main

**Step 2 — Safety check:**
If the current branch is `main` or `master`, STOP and tell the user. Never commit directly to main.

**Step 3 - Quality check:**
- Always Ask the user if it is required to run `bundle exec rspec` on the entire test suite or only on the test that may be affected by the changed sources in this commit files.
- Run `bundle exec rspec <files>` on those files
- Debug the tests until specs affected by changes in this branch.

**Step 4 — Lint changed Ruby files:**
- Get the list of changed `.rb` files: `git diff main...HEAD --name-only -- '*.rb'`
- Run `bundle exec rubocop <files>` on those files.
- If there are auto-correctable offenses, run `bundle exec rubocop -A <files>` to fix them.
- If rubocop made changes, stage and commit them with message: "Fix rubocop offenses"
- If non-auto-correctable offenses remain, show them to the user and ask how to proceed.

**Step 5 — Security scan:**
- Run `bundle exec brakeman -q --no-pager` to check for security warnings.
- If warnings are found, show them to the user with file and line numbers.
- Attempt to fix each warning (XSS, SQL injection, open redirect, etc.).
- If fixes were made, stage and commit them with message: "Fix brakeman security warnings"
- If warnings remain that cannot be auto-fixed, show them and ask how to proceed.
- Do NOT create the PR with unresolved high-confidence warnings.

**Step 6 — Draft the commit message:**
- Summarize the nature of the changes in one concise subject line (≤72 chars)
- Use imperative mood: "Add", "Fix", "Update", "Remove" — not "Added" or "Adds"
- Focus on the *why*, not the *what*
- If the changes span multiple concerns, note that and ask the user whether to split

**Step 7 — Stage and commit:**
- Stage specific files by name (avoid `git add -A` or `git add .`)
- Create the commit using a HEREDOC to preserve formatting:

```
git commit -m "$(cat <<'EOF'
Subject line here

Optional body explaining why.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

**Step 8 — Confirm:**
Run `git status` to verify the working tree is clean.

**Arguments:** $ARGUMENTS
If the user passed arguments, treat them as guidance for the commit message or scope (e.g., `/commit fix auth bug` → focus the message on the auth fix).
