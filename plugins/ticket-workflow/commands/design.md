---
model: opus
---

Design how to build something whose problem is already settled: compare approaches, pressure-test the choice, and write the durable plan.

**Arguments:** `$ARGUMENTS` — a GitHub issue number or URL, or a free-text description of the work.

## Precondition

The *what* is decided. This skill answers *how*. If the problem itself is still
open — if you find yourself asking whether this is the right thing to build —
stop and go back to `/architect`.

If the argument is an issue number or URL, read the issue first. It is the
statement of the problem; do not re-litigate it here.

## 1 — Ground

Read the code that will actually change, and the project's conventions
(`CLAUDE.md` first, then any `*_ARCHITECTURE.md`, ADRs, or design notes that bear
on this area). Cite `file:line`. Verify how things work — don't speculate.

Identify the constraints that genuinely bind here: security, tenancy,
performance, and the project's own rules.

## 2 — Place the behavior

Invoke the design skills the project keeps for this — at minimum
`behavior-placement` (where the behavior belongs, and whether the app already
derives the answer) and `codebase-design` (how deep a module should be:
interface, seam, depth, leverage). Use whatever others the project has added.

These are steps, not background reading. Run the placement checks against every
approach that adds or moves a class, and use the design vocabulary exactly when
comparing approaches — it is the scoring axis, not decoration.

## 3 — Compare approaches

- Present 2-3 concrete approaches with trade-offs.
- For each: what changes, what's the blast radius, what are the risks?
- Reference how similar problems are already solved in this codebase.
- Discuss incrementally. Don't dump everything at once — respond to the user's
  reactions.

## 4 — Grill the choice

Once a direction emerges, invoke `grilling` on it. A discussion converges on
whatever it drifted toward; grilling is the adversarial pass that catches the
decision nobody actually argued about. Do not skip it because the direction feels
settled — that feeling is the trigger. If grilling surfaces an unresolved
decision, go back to step 3 for that branch.

## 5 — Write the plan

Summarize the agreed approach, what can be done incrementally vs. what requires a
big-bang change, and any open questions that must be answered before
implementation.

Then write `plans/<issue-number>-plan.md` — or `plans/<short-slug>-plan.md` if
there's no issue. Resolve `plans/` against the repository root via
`git rev-parse --show-toplevel` from the main checkout rather than hardcoding a
path; `mkdir -p` it if needed. Add `/plans` to `.gitignore` if it isn't there
already: the directory must stay out of the repo, persist across sessions, and be
symlinked into every worktree by `/start-ticket`. That combination is what makes
a plan written here the durable handoff `/start-ticket` picks up later, even from
a fresh worktree.

Keep it short. Capture the durable reasoning the lean issue intentionally omits —
the *why* behind the approach and the alternatives rejected — NOT file lists or
line numbers that will rot.

```markdown
# Issue #<number>: <title>

## Context & Motivation
[Why this matters, what prompted it]

## Agreed Approach
[The direction converged on — intent level]

## Key Decisions & Trade-offs
[Decisions made and why alternatives were rejected — the durable reasoning]
```

Only decisions that were actually examined belong in that last section — in
practice, the ones grilling put pressure on. A mechanism nobody argued about is
an assumption, and writing it beside genuine trade-offs launders it into one: the
implementer can't tell which line cost an hour of discussion and which was typed
in passing. Leave it out. If a substrate really does need naming, mark it
provisional and say what would change it.

Tell the user the plan will be picked up by `/start-ticket`.

## Never

- Make implementation changes. This is design only.
- Re-open the problem statement. That's `/architect`.
- Skip the grilling pass because the direction looks obvious.
