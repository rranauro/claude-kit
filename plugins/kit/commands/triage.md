---
model: opus
---

Take an issue that arrived and settle it — bin it, fix its scope, design it, and publish the brief on the issue so an agent can pick it up unattended.

**Arguments:** `$ARGUMENTS` — a GitHub issue number or URL. With no argument,
list the open issues that are not yet agent-ready and work them one at a time.

## What this is for

`/kit:start-ticket` qualifies an issue as settled when its body states testable
acceptance criteria and what's out of scope. Nothing in the workflow *produces*
such a body except `/kit:design`, and `/kit:design`'s output lands in a gitignored
local `plans/` directory that dies with the machine. So the agent-ready path is
reachable only by writing the brief by hand, ungrilled.

This command is the missing producer. It ends with the brief on the issue.

**One issue at a time, with approval before anything is written.** Never sweep a
list applying labels. The reason to work a queue here is that the *scope* pass
below is cheaper in a batch, not that the writing can be automated.

## 1 — Bin it

Read the issue and its comments. Before designing anything, decide whether it
should exist:

- **Already fixed** — verify against the code, don't take the issue's word. Close
  with the commit or PR that did it.
- **Duplicate** — close, and comment on both sides with the link.
- **Not now** — the problem is real but the moment isn't. Say why in a comment and
  leave it open, unlabelled. Parking is a decision; record it so the next triage
  pass doesn't re-derive it.
- **Not a ticket** — a question, a support request, a design conversation that
  hasn't earned an issue. Answer it, or point it at `/kit:architect`.
- **Already settled** — see below. The rest of the command is skipped.

Most of the value of triage is the tickets that never reach step 2. Don't rush
this to get to the interesting part.

### Already settled

A project that writes good tickets will hand you issues that need nothing from
steps 2–3. Running the full pass on one of those is redesigning settled work in
order to apply a sticker. Check for it first.

It's settled when **both** hold, judged from the body and comments you already
read:

1. The body states **testable acceptance criteria** and **what's out of scope** —
   the same test `/kit:start-ticket` applies, so passing it means the ticket is
   already implementable.
2. The approach has been through a design pass — a `plans/<n>-plan.md` exists, or
   the issue carries a brief recording the direction and the alternatives
   rejected.

Criterion 1 alone is not enough. A well-written ticket can state crisp criteria
over a decision nobody has made — an either/or in the body, or a criterion
conditional on an answer ("if X is chosen, then…"). That ticket *qualifies* for
`/kit:start-ticket` and will still be decided unilaterally by whoever implements
it, in a diff, with nothing recording that a choice was made. It is precisely
what this command exists for. Send it to step 2.

When it is settled, the only thing left is step 4's label decision. Say what you
found, confirm, apply, stop. Don't re-grill and don't re-run `/kit:design`.

**Overrides, in both directions:**

- The user can ask for the full pass on a settled ticket. Run it. "Settled" is a
  judgement about the artifact, not a lock.
- Go to step 2 anyway when the ticket is settled *stale* — the design pass
  predates work that has since landed in the same area, or a linked issue has
  re-scoped it. Say why rather than silently reopening.
- A ticket that only needs the label, and that you have no doubts about, is a
  fine thing to confirm in a single turn. That is the command working, not
  skipping.

## 2 — Grill the scope

This is the pass that does not exist anywhere else in the workflow, and it runs
*before* any approach is compared — because it changes what is being designed.

Invoke `grilling` on the ticket's **boundary**, not its approach:

- Which adjacent decisions does implementing this force, that the ticket doesn't
  settle? Whoever implements it will answer them by picking whatever is locally
  obvious, and the answer will be invisible in the diff.
- Of those, which fold in *now*? Folding is nearly free here and expensive later:
  once an approach has been priced against the narrow scope, widening means
  re-pricing.
- Which are genuinely separate work, and should be filed as their own tickets
  rather than absorbed?
- Is the ticket too wide — two unrelated outcomes sharing a title, so no single
  PR can be reviewed against it?

The output is a settled scope: unchanged, widened, narrowed, or split. **Present
any scope change to the user before going further.** A widened ticket is a
commitment to a bigger PR and that is the user's call, not yours.

If the answer is "split," use `kit:writing-tickets` for the new issues and slice
them vertically — it owns that decision, don't re-derive the rules here.

A ticket whose scope survives this pass unchanged is a normal outcome, not a
wasted step. The pass is cheap; the follow-up ticket it prevents is not.

**This is the cheap first look, not the last word.** You're grilling the boundary
without the code open, so you'll catch the decisions that are obvious from the
problem and miss the ones only visible in the source. `/kit:design` reads the
code and may move the boundary again — that's the intended order, not a failure
here. Set the scope you can defend and hand it over; don't stall trying to reach
one design can't improve on.

## 3 — Design the how

Run `/kit:design` on the settled scope, telling it to publish to the issue (see
its **Where the brief goes** section). It owns grounding in the code, behavior
placement, comparing approaches, and grilling the choice. Do not reimplement any
of that here, and do not skip it because step 2 made the work feel obvious —
step 2 grilled the boundary, which is a different question from the mechanism.

## 4 — Publish

`/kit:design` has posted the brief — or, on the already-settled path, the brief
was already there and this is the only step that runs. Two things remain, and
both need the user's approval:

**Bring the issue body up to the bar.** The brief is reasoning; the body has to
state **testable acceptance criteria** and **what is out of scope**. That pair is
the whole of `/kit:start-ticket`'s qualification test — an issue missing either
falls back to `/kit:design` when it's picked up, which is exactly the round trip
this command exists to prevent. Write outcomes in domain vocabulary and keep
substrate out of them; `kit:writing-tickets` owns that.

Say in the body that only the acceptance criteria are binding. Without it,
`/kit:start-ticket` reads the whole body as settled and won't relitigate a
direction that was a guess.

**Apply the AFK-ready label** — `ready-for-agent` in the canonical vocabulary,
or the project's own mapping where it differs.

Be clear with the user about what the label does, because it is narrower and
heavier than "this ticket is vetted":

- It is *not* what makes the issue qualify for `/kit:start-ticket`. That reads
  the body; the label is corroboration and a staleness date.
- It does *not* route the work or choose who implements. `/kit:ship-ticket`
  never reads it.
- Its one behavioral effect is that **`/kit:tend-prs` will start this ticket
  unattended**, on a loop, with nobody watching.

So the question to put is not "is this ready?" but "is this safe to begin with
no one watching?" Those come apart.

**A blocking dependency is not a reason to withhold the label.** `start-next`
only picks up a ticket whose `kit-blocked-by` marker is fully closed, so the edge
already holds it back. Withholding as well is redundant, and it defeats the
mechanism: a labelled ticket starts itself the moment its blocker merges, while
an unlabelled one waits for a manual pass nobody has scheduled. Record the edge
in the marker, then label it.

**An unresolved decision is.** `start-next` invokes `/kit:ship-ticket` under a
no-questions constraint, so a ticket that still carries an open design question
gets that question answered unattended, inside a diff, by whichever agent picked
it up. That is the failure this command exists to prevent, arriving through the
back door. Hold the label until the decision is made — and note that this is the
same evidence step 1 uses to refuse the already-settled short-circuit, so a
ticket that legitimately reached step 2 for want of a design pass must not leave
step 4 labelled unless that pass actually happened.

Also hold it for a step no agent should take alone regardless of the design being
settled: a data migration that must reconcile production, anything destructive,
anything whose blast radius the acceptance criteria don't bound.

Say which of these applies rather than just declining. Confirm the label as its
own decision rather than folding it into the publish.

## Staleness

An agent-ready issue is designed to sit in the queue, so its brief ages in a way
a plan written an hour ago does not. Nothing here can prevent that, and
`/kit:start-ticket` already re-verifies anchors before implementing. Don't add a
freshness claim to the body that will itself go stale — the label's application
date is the timestamp, and that command knows to read it.

## Never

- Make implementation changes. This command designs and publishes; it writes no code.
- Apply the agent-ready label to more than one issue without individual approval.
- Widen a ticket's scope without telling the user it got wider.
- Skip step 3's grilling because step 2 already grilled something.
