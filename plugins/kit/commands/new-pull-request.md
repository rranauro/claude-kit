Create a GitHub pull request for the current branch.

Always run `/kit:commit` first and confirm the branch is ready for a pull request.

**Step 1 — Push the branch:**
- If the branch has not been pushed or is behind, push it with `git push -u origin <branch>`.

**Step 2 — Analyze all changes:**
- Read the full diff with `git diff main...HEAD` to understand every change.
- Review ALL commits (not just the latest) to build a complete picture.
- If the branch name starts with a number (e.g., `218-...`), that's the issue number.

**Step 3 — Write the body with `kit:visual-pr`, then create the PR:**

Invoke `kit:visual-pr` via the Skill tool for the body, passing the issue number
and `unattended` if the arguments carry it. It is the only body this command
writes: `kit:visual-review` reads exactly its sections, and a second format is
a PR the review skill cannot rely on. It also writes the issue reference.

- Title: short, imperative, under 72 characters. Captures the primary change.
- **If the arguments carry a `draft` token, add `--draft`.** A caller asks for
  that when it intends to close the review round itself before the PR is ready
  to merge; without the token nothing here changes.

```
gh pr create --title "the pr title" --body-file <the visual-pr-body.md it wrote, plus the trailer>
```

Name the running model in the trailer if you know it (e.g.
`Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`); otherwise leave it as
`Claude`. Do not hardcode a model version in this file — it goes stale.

**Step 3b — Carry a hold forward, if the issue asked for one:**

If this PR names an issue — `Closes` or `Part of` — check whether that issue
carries `kit-hold`:

```
gh issue view <issue-number> --json labels -q '.labels[].name'
```

If it does, apply the same label to the new PR immediately, before printing the
URL:

```
gh pr edit <pr-number> --add-label kit-hold
```

**If that write is refused, say so and do not print the URL as if the PR were
held.** The repo may not have the label, and the grant denies `gh label`. A hold
the gate cannot see is a PR that merges — the exact outcome the human's answer
ruled out — so report which label failed and that the PR is *not* held until
someone applies it. `docs/labels.md` carries the fix; never create the label
yourself.

This is not the automation deciding to hold something. A human answered that
question when the ticket was settled, and this step transcribes the answer onto
the artifact it was about. Holds a pass decides for itself are written later, by
`kit:ticket-loop` `hand-off`, with their reason posted first. Nothing unattended
ever clears this label, which is the rule that matters: a pass cannot clear a
hold it is subject to.

**Only if that edit succeeded**, say in the confirmation that the PR is held and
how to release it, since a held PR looks identical to an ignored one:

> PR #<N> is open and **held** (`kit-hold`) — the CI gate will skip it entirely.
> Remove the label when you're done verifying, and it picks up from there.

Where it was refused, say the opposite in its place: the PR is open and **not**
held, it will merge when checks pass, and `gh label create kit-hold` followed by
this same edit is what holds it.

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
<One paragraph: the problem being solved or the root cause addressed — the Gist, in prose>

## Key Decisions
<Bullet list of non-obvious choices made — trade-offs, alternatives rejected, architectural constraints>

## Files Touched
<`git diff --stat main...HEAD`, grouped by concern>
```

Create the `tickets/` directory if it doesn't exist. Tell the user the file has been saved.

**Arguments:** $ARGUMENTS
Bare `draft` and `unattended` tokens are read by Step 3 and are not guidance.
`unattended` is passed by a caller that knows nobody is watching; never infer it.
Anything else is
guidance for the PR title, scope, or target branch (e.g.,
`/kit:new-pull-request ready for review` → mention readiness in the description).
