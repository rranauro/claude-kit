---
model: sonnet
---

Reclaim this repo's worktrees — one named target, or a sweep of all of them.

**Arguments:** `$ARGUMENTS` — optionally a branch name, a worktree path, or a PR
number. With none, sweep every linked worktree.

Run it from the main checkout.

If the argument is a PR number, resolve it to a branch first:
`gh pr view <num> --json headRefName`.

Then run the `kit:worktree-reclaim` skill, attended: it stops after the verdicts
and asks before removing anything. It owns the phases, the two tests, and what
the report has to name.
