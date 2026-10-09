---
name: reclaim-sweep
description: Sweep this project's dead worktrees unattended and hand back what was reclaimed and what was held. Use when /kit:ship-ticket opens its run.
model: haiku
effort: low
---

Invoke the `kit:worktree-reclaim` skill through the Skill tool, unattended and
with no target, so it sweeps every worktree and asks nothing. Follow it as
written; the judgement it leaves you is small, and its script does the rest.

Hand back only what the sweep did:

- what was reclaimed — each directory removed and each branch deleted, with what
  accounted for the branch;
- what was held or skipped — each worktree and branch kept, with its reason.

Say so when it reclaimed nothing, and say so when it failed. No per-worktree
inventory beyond that: the session that launched you is carrying a ticket, and
the survey is what this sweep runs isolated to keep out of it.
