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

Most of the value of triage is the tickets that never reach step 2. Don't rush
this to get to the interesting part.

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

`/kit:design` has posted the brief. Two things remain, and both need the user's
approval:

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
or the project's own mapping where it differs. This is what makes the issue
visible to `/kit:tend-prs`, which sweeps by label for work to start unattended.
It is *not* what makes it qualify for `/kit:start-ticket` — that reads the body.
Applying it is a statement that you're content for an agent to start this without
asking again, so confirm it as its own decision rather than folding it into the
publish.

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
