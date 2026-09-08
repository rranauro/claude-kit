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
- **If the arguments carry a `draft` token, add `--draft`.** A caller asks for
  that when it intends to close the review round itself before the PR is ready
  to merge; without the token nothing here changes.

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

**Step 3b — Carry a hold forward, if the issue asked for one:**

If this PR closes an issue, check whether that issue carries `kit-hold`:

```
gh issue view <issue-number> --json labels -q '.labels[].name'
```

If it does, apply the same label to the new PR immediately, before printing the
URL:

```
gh pr edit <pr-number> --add-label kit-hold
```

This is not the automation deciding to hold something. A human answered that
question when the ticket was settled, and this step transcribes the answer onto
the artifact it was about. Nothing unattended ever writes this label in either
direction, which is the rule that matters: a pass cannot clear a hold it is
subject to.

Say in the confirmation that the PR is held and how to release it, since a held
PR looks identical to an ignored one:

> PR #<N> is open and **held** (`kit-hold`) — the CI gate will skip it entirely.
> Remove the label when you're done verifying, and it picks up from there.

**Step 4 — Confirm:**
Print the PR URL so the user can review it.

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
A bare `draft` token is read by Step 3 and is not guidance. Anything else is
guidance for the PR title, scope, or target branch (e.g.,
`/kit:new-pull-request ready for review` → mention readiness in the description).
