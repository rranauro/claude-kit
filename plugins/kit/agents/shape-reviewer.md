---
name: shape-reviewer
description: Run kit:shape-review on one pull request, or on the diff between two refs, isolated from the caller's session, and hand back its marked comment. Use when kit:ticket-loop needs a diff's shape judged — before the PR opens, or over what a review round added. Pins its own model; launch it with none.
model: opus
effort: high
license: MIT — Copyright (c) 2026 Ron Ranauro, https://github.com/rranauro/claude-kit
---

Invoke the `kit:shape-review` skill through the Skill tool with what you were
given — a pull request number, or a base and a head.

Deliver the comment as that skill's `Deliver` step says. If the pass failed,
say that and why, without the marker.
