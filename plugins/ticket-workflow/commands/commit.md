Create a git commit for the current changes.

Stack-agnostic: the toolchain is read from the project, never assumed. Projects
that want a gate enforced rather than remembered should register a hook — see
`hooks/rails-quality-gates.sh` for the Rails example. This command handles the
part a hook can't: deciding what a finding means and fixing it.

**Step 1 — Situational awareness (run in parallel):**
- `git status` — see all modified and untracked files (never use -uall)
- `git diff HEAD` — see all staged and unstaged changes
- `git log --oneline -10` — see recent commit message style and conventions
- `git rev-parse --abbrev-ref HEAD` — confirm we are NOT on main or master
- `git diff main...HEAD --stat` — see file-level summary of all changes vs main

**Step 2 — Safety check:**
If the current branch is `main` or `master`, STOP and tell the user. Never commit directly to main.

**Step 3 — Identify the project's quality gates:**

Do not guess the toolchain. Read it from the project, in this order, and stop at
the first that answers:

1. `CLAUDE.md` — if it names the test/lint/security commands, use those verbatim.
2. The manifest and its scripts — `package.json`, `Makefile`, `Gemfile`,
   `pyproject.toml`, `Cargo.toml`, `go.mod`.
3. CI config — `.github/workflows/*.yml` runs the commands the project actually
   considers authoritative.

If none of those answer, ask the user how to run tests and linting rather than
inventing a command. A wrong command that errors is noise; a wrong command that
silently passes is worse.

**Step 4 — Run the gates on what changed:**

- **Tests.** Derive the target set explicitly rather than saying "the affected
  tests" and improvising:
  1. List the changed sources: `git diff main...HEAD --name-only`.
  2. Map each to its test by the project's own convention — `app/models/foo.rb` →
     `spec/models/foo_spec.rb` under RSpec, `src/foo.ts` → `src/foo.test.ts`
     under Jest, and so on. Read an existing pair to confirm the convention
     before trusting it.
  3. A changed file that *is* a test runs as itself.
  4. Run that set. Anything you couldn't map, say so — an unmapped source is a
     coverage gap worth naming, not a file to quietly skip.

  Targeted runs need no permission. Only the full suite does — ask before that,
  and don't ask before the targeted run.
- **Lint/format:** run the project's linter on the changed files. If it has a
  safe autofix mode, apply it and stage the result.
- **Security scan:** if the project has one wired up, run it. Show any findings
  with file and line numbers and attempt a fix. Do not commit unresolved
  high-confidence warnings without telling the user.
- If a gate does not exist for this project, skip it and say so — don't
  substitute a different tool.

**Step 5 — Draft the commit message:**
- Summarize the nature of the changes in one concise subject line (≤72 chars)
- Use imperative mood: "Add", "Fix", "Update", "Remove" — not "Added" or "Adds"
- Focus on the *why*, not the *what*
- If the changes span multiple concerns, note that and ask the user whether to split

**Step 6 — Stage and commit:**
- Stage specific files by name (avoid `git add -A` or `git add .`)
- Create the commit using a HEREDOC to preserve formatting:

```
git commit -m "$(cat <<'EOF'
Subject line here

Optional body explaining why.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

Name the running model in the trailer if you know it (e.g.
`Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`); otherwise leave it as
`Claude`. Do not hardcode a model version in this file — it goes stale.

**Step 7 — Confirm:**
Run `git status` to verify the working tree is clean.

**Arguments:** $ARGUMENTS
If the user passed arguments, treat them as guidance for the commit message or scope (e.g., `/commit fix auth bug` → focus the message on the auth fix).
