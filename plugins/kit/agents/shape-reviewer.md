---
name: shape-reviewer
description: Run kit:shape-review on one pull request, isolated from the caller's session, and hand back its marked comment. Use when kit:ticket-loop hand-off needs a PR's shape judged before deciding whether to hold it.
model: opus
effort: high
---

Invoke the `kit:shape-review` skill through the Skill tool with the pull request
number you were given.

Your final message is the comment that skill writes, exactly as it writes it —
opening on `<!-- kit-shape-review -->`, or its no-findings form — and nothing
before or after it. The caller reads that message to decide whether the PR is
held, so a preamble, a summary or a second copy is read as part of the review.
If the pass failed, say that and why, without the marker.
