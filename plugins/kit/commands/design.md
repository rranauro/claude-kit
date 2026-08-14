---
model: opus
---

Design how to build something whose problem is already settled: compare approaches, pressure-test the choice, and write the durable plan.

**Arguments:** `$ARGUMENTS` — a GitHub issue number or URL, or a free-text description of the work.

## Precondition

The *what* is decided — by `/kit:architect`, by `/kit:triage`, or by the user
saying so. This skill answers *how*. If the problem itself is still open — if you
find yourself asking whether this is the right thing to build — stop and go back
to `/kit:architect`.

"Decided" includes a scope that `/kit:triage` just widened or narrowed. Start from
the scope your caller hands you, not the one the issue body was opened with.

**On scope, the pass closest to implementation wins — and that's this one.**
`/kit:architect` set the boundary without the code open; `/kit:triage` grilled it
with the code closed too. You are the first pass reading what actually has to
change, so if you find the boundary drawn in the wrong place — a decision this
work forces that the ticket leaves dangling, or scope the code shows is two
things — say so and move it. Deferring to an earlier pass that knew less is how a
ticket ships correct-to-spec and wrong.

This is not licence to drift. A widening costs something specific, so it has to
be paid for:

- **Tell the user it got wider, as its own question.** Not folded into an
  approach comparison. They're agreeing to a bigger PR.
- **Write it back to the issue's acceptance criteria.** A widening changes the
  observable outcome, which is the one reason `kit:writing-tickets` allows a
  criterion to be revisited. Skip this and the PR stops matching the ticket it
  closes, and the reviewer can't tell agreed work from improvised work.
- **Prefer splitting to absorbing** when the extra scope stands on its own. Two
  reviewable tickets beat one PR that does two things.

Narrowing takes the same treatment. Silently building less than the criteria ask
for is the same defect wearing the other sign.

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
`kit:behavior-placement` (where the behavior belongs, and whether the app already
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

Then publish it. Where depends on who called — see **Where the brief goes** below.

### Where the brief goes

**Invoked by `/kit:triage`, or asked to publish to the issue:** post the brief as
a comment on the issue. That copy survives the machine and is readable by an
agent that never had your `plans/` directory — which is the point of publishing
there rather than locally. Also write the local plan file below when there is an
issue number to name it with; it costs nothing and keeps the offline handoff
working. On conflict the plan file wins, and `/kit:start-ticket` already knows
that.

**Invoked directly (the default):** write the local plan file only. Don't post to
the issue unasked — a comment is public and permanent, and the user came here to
think, not to publish.

### The local plan file

Write `plans/<issue-number>-plan.md` — or `plans/<short-slug>-plan.md` if
there's no issue. Resolve `plans/` against the repository root via
`git rev-parse --show-toplevel` from the main checkout rather than hardcoding a
path; `mkdir -p` it if needed. Add `/plans` to `.gitignore` if it isn't there
already: the directory must stay out of the repo, persist across sessions, and be
symlinked into every worktree by `/kit:start-ticket`. That combination is what makes
a plan written here the durable handoff `/kit:start-ticket` picks up later, even from
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

Tell the user the plan will be picked up by `/kit:start-ticket`. If you were
invoked by `/kit:triage`, say nothing about handoff and return — it has its own
publish step to finish, including the hold question below.

**When the brief lands on an issue and you were *not* invoked by `/kit:triage`,
ask whether the PR should be held:**

```
Hold the PR for in-app verification before it merges? (y/N)
```

If yes, `gh issue edit <n> --add-label kit-hold`. `/kit:new-pull-request`
transcribes it onto the PR, so the hold is in place before a tending pass can
reach it.

You have just spent a conversation on how this will be built, which is the most
informed anyone will be about whether the result needs *seeing* before it merges.
Waiting until the PR exists means racing a scheduled pass with the answer you
already had. Default to no — a bare Enter — and say yes when the approach you
just settled produces something you have to look at rather than something a test
asserts.

Only ask when there is an issue to label; a plan written to a local file has no
PR coming.

## Never

- Make implementation changes. This is design only.
- Re-open the problem statement. That's `/kit:architect`.
- Skip the grilling pass because the direction looks obvious.
