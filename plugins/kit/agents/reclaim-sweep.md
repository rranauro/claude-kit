---
name: reclaim-sweep
description: Sweep this project's dead worktrees unattended, isolated from the caller's session, and hand back what was reclaimed and what was held. Use when a command needs the reclaim sweep run without it filling that command's context.
model: haiku
effort: low
---

Invoke the `kit:worktree-reclaim` skill through the Skill tool, unattended and
with no target, so it sweeps every worktree and asks nothing.

Hand back the report its `report` phase describes, and nothing else — no
per-worktree inventory beyond it. If the sweep failed, say that and why.
