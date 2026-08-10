Create a GitHub pull request for the current branch.

Always run `/kit:commit` first and confirm the branch is ready for a pull request.

**Step 1 — Push the branch:**
- If the branch has not been pushed or is behind, push it with `git push -u origin <branch>`.

**Step 2 — Analyze all changes:**
- Read the full diff with `git diff main...HEAD` to understand every change.
- Review ALL commits (not just the latest) to build a complete picture.
- Group changes by concern (e.g., "typography improvements", "new rake task", "prompt updates").

**Step 3 — Draft and create the PR:**
- Title: short, imperative, under 72 characters. Captures the primary change.
- Body: use the format below. Be specific — reference actual files, methods, and config keys.
- If the branch name starts with a number (e.g., `218-...`), that's the issue number — link it with `Closes #218`.

```
gh pr create --title "the pr title" --body "$(cat <<'EOF'
## Summary
<3-5 bullet points describing what changed and why>

## Details
<Paragraph or two explaining the motivation, approach, and any trade-offs>

## Changes
<Grouped list of specific changes by area>

## Test plan
- [ ] <specific testing steps>

Closes #<issue-number-if-applicable>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

Name the running model in the trailer if you know it (e.g.
`Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`); otherwise leave it as
`Claude`. Do not hardcode a model version in this file — it goes stale.

**Step 4 — Confirm:**
Print the PR URL so the user can review it.

**Step 4a · `start-polling` — Point at the sweeper, don't poll:**
GitHub Copilot reviews PRs automatically and usually takes 3–5 minutes; the local Claude headless review can land later still. Waiting for either here would hold the session open to do work that needs nobody present — `/kit:tend-prs` does it out of session, across every open PR at once.

Check whether the sweeper is already running (`/loop` reports its active loops). Then tell the user one of:

> "PR #<N> is open. `/loop 20m /kit:tend-prs` is already running — it'll triage the reviews, push fixes, and enable auto-merge without you."

> "PR #<N> is open. Start `/loop 20m /kit:tend-prs` to have the reviews triaged and merged unattended, or run `/kit:tend-prs` once by hand after they post."

Do not start the loop yourself. It binds to the current session, and starting a second one silently leaves two sweepers with no clear owner.

**Step 5 — Save ticket context to `tickets/`:**
After the PR is created, write a summary file to `tickets/<pr-number>-<branch>.md`. It records why the change was made for whoever debugs it later — `/target-debug` reads these if you have it installed, and they stand on their own if you don't. Add `tickets/` to `.gitignore` if it isn't there already; these are local working notes, not repo content.

Format:
```markdown
# PR #<number>: <title>

## Branch
<branch-name>

## Why
<One paragraph: the problem being solved or the root cause addressed>

## Key Decisions
<Bullet list of non-obvious choices made — trade-offs, alternatives rejected, architectural constraints>

## Files Touched
<Grouped list matching the Changes section of the PR body>
```

Create the `tickets/` directory if it doesn't exist. Tell the user the file has been saved.

**Arguments:** $ARGUMENTS
If the user passed arguments, treat them as guidance for the PR title, scope, or target branch (e.g., `/kit:new-pull-request ready for review` → mention readiness in the description).
