Create git commits for the current changes, split by concern.

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

  **Run named files and examples only — never a directory or the whole suite
  without asking.** A path argument with no filename is the form this rule exists
  to catch; it reads as a modest widening and is where the minutes go. CI runs the
  full sweep on the PR anyway. Targeted runs need no permission — don't ask.
- **Lint/format:** run the project's linter on the changed files. If it has a
  safe autofix mode, apply it and stage the result.
- **Security scan:** if the project has one wired up, run it. Show any findings
  with file and line numbers and attempt a fix. Do not commit unresolved
  high-confidence warnings without telling the user.
- If a gate does not exist for this project, skip it and say so — don't
  substitute a different tool.

**Step 5 — Group the changes into commits:**

Default to more than one. A commit is one reviewable unit: a reviewer should read
it, understand the single concern it settles, and move on. A branch's worth of
unrelated work in one commit forces them to hold all of it at once.

Group so that:

- Code and its tests land **together**, never split across commits.
- A schema migration is always its own commit.
- A refactor is separate from new behaviour, even in the same file.
- Unrelated config or tooling changes stand alone.

Order by dependency — whatever a later commit reads must already exist by then.
In a Rails project that runs migration → model → service → controller → view. The
principle is the same anywhere: schema before the code reading it, the data layer
before its callers, callers before presentation.

Show the planned breakdown before executing — each commit with its files and its
proposed subject — and ask the user to confirm. If the change genuinely is one
concern, say so and commit once; the point is that splitting is the default, not
that every change must be split.

**Step 6 — Draft each commit message:**
- Summarize the nature of the changes in one concise subject line (≤72 chars)
- Use imperative mood: "Add", "Fix", "Update", "Remove" — not "Added" or "Adds"
- Focus on the *why*, not the *what*

**Step 7 — Stage and commit each group:**
- Stage specific files by name (avoid `git add -A` or `git add .`)
- Commit each group in dependency order, so the tree builds at every step
- Create each commit using a HEREDOC to preserve formatting:

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

**Step 8 — Confirm:**
Run `git status` to verify the working tree is clean, and
`git log --oneline main..HEAD` to show the user the commits as a set.

**Arguments:** $ARGUMENTS
If the user passed arguments, treat them as guidance for the commit message or scope (e.g., `/kit:commit fix auth bug` → focus the message on the auth fix).
