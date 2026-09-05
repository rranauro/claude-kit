---
model: opus
---

Take an issue that arrived and settle it — bin it, fix its scope, design it, and publish the brief on the issue so an agent can pick it up unattended.

**Arguments:** `$ARGUMENTS` — a GitHub issue number or URL. With no argument,
list the open issues that are not yet agent-ready and work them one at a time.

## What this is for

`kit:start-ticket` qualifies an issue as settled when its body states testable
acceptance criteria and what's out of scope. `/kit:design` stores the reasoning
behind that — but reasoning is not acceptance criteria, and nothing else in the
workflow brings the *body* up to the bar. So the agent-ready path is reachable
only by writing it by hand, ungrilled.

This command is the missing producer. It grills the scope, runs `/kit:design`,
and ends with a body an agent can pick up unattended.

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

### Assign the kind

A ticket **leaves this step carrying exactly one kind label** — the project's
mapping owns the strings; the canonical five are `bug`, `enhancement`,
`improve-codebase`, `technical-debt`, and `user-experience`. Two kinds is two
answers to one question, and nothing downstream picks a winner.

That is a post-condition, not an instruction to apply one: act when a ticket
carries no kind, or two.

The kind is not a topic. It answers one question: **can this ticket's acceptance
be asserted without a human eye?** A test that goes green, a shape count,
behavior preserved across a refactor — those are yes. A rendered view, an
interaction, a thing someone has to look at — that is `user-experience`.
Subject-matter labels (`cli`, `Security`, `performance`, …) carry no kind and
stack freely alongside it.

This is the switch the unattended design pass reads, which is why it is assigned
here rather than inferred later: every kind but `user-experience` can be designed
with nobody present, because its acceptance criteria hold the result to
something checkable. `user-experience` cannot, and parks for a human at the
design pass.

**`bug` and `enhancement` differ only in provenance, and nothing downstream reads
the difference.** So there is deliberately no rule for choosing between them: a
mislabelling is free, and a rule would imply a cost that does not exist. What is
not free is reaching for either when the ticket's *design* needs a human — an
addition someone has to look at is `user-experience`, the same as a fix would
be.

**`improve-codebase` and `technical-debt` are one subject split by provenance,
and that is deliberate.** Structural work the
`kit:improve-codebase-architecture` scan surfaced is `improve-codebase`;
structural work a human noticed is `technical-debt`. Unlike the pair above, where
it came from is what fixes how acceptance is asserted — the scan states the
object-shape counts it found, so the change is held to those, while a
human-surfaced one has only the standing claim that behavior is preserved. Both
are AFK-eligible. Only the scan applies `improve-codebase`; triage never does.

**So a ticket can arrive already wearing its kind.** One the scan filed carries
`improve-codebase` before this command ever sees it, and the post-condition is
met on arrival — leave the label where it is. Do not reach for `technical-debt`
because the ticket reads as human-surfaced. Nothing on an issue records which
pass produced it, so the label is the only evidence of provenance there is, and
rewriting it destroys the distinction the split exists to draw. Read it, the way
this command already reads `kit-blocked` and `epic`; adjudicating it is not this
step's job. Every step after this one runs unchanged.

**Kind does not decide `kit-hold`** — see step 4. It decides who has to be
present while the approach is chosen, not whether the result must be walked.

### Already settled

A project that writes good tickets will hand you issues that need nothing from
steps 2–3. Running the full pass on one of those is redesigning settled work in
order to apply a sticker. Check for it first.

It's settled when **both** hold, judged from the body and comments you already
read:

1. The body states **testable acceptance criteria** and **what's out of scope** —
   the same test `kit:start-ticket` applies, so passing it means the ticket is
   already implementable.
2. A **plan artifact** exists — the marked `plan` comment that
   `kit:ticket-artifacts` resolves from the cache or the issue, or the same
   content written inline in the body under its own heading. Either form counts;
   what makes it an artifact is that a reader can point at the block and say
   *this is the agreed approach and these are the alternatives it beat*.

**Direction in the body is not a plan.** A ticket that reads as confident, names
a class, or gestures at how it should work has recorded an author's intent, not a
decision — nothing says what else was considered or why it lost, so nothing
downstream can tell a settled choice from a first guess. Judging that by feel is
what made this test too loose to act on: an artifact is present or it isn't, and
a strong-sounding body is exactly the case that used to pass and shouldn't. If
the direction is genuinely settled, step 3 costs little and produces the block
that says so.

Criterion 1 alone is not enough. A well-written ticket can state crisp criteria
over a decision nobody has made — an either/or in the body, or a criterion
conditional on an answer ("if X is chosen, then…"). That ticket *qualifies* for
`kit:start-ticket` and will still be decided unilaterally by whoever implements
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

Invoke `kit:grilling` on the ticket's **boundary**, not its approach:

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

Run `/kit:design` on the settled scope. It stores the plan on the issue on its
own now — you no longer have to ask it to. It owns grounding in the code, behavior
placement, comparing approaches, and grilling the choice. Do not reimplement any
of that here, and do not skip it because step 2 made the work feel obvious —
step 2 grilled the boundary, which is a different question from the mechanism.

## 4 — Publish

`/kit:design` has stored the plan — or, on the already-settled path, it was
already there and this is the only step that runs. Two things remain, and both
need the user's approval:

**Bring the issue body up to the bar.** The brief is reasoning; the body has to
state **testable acceptance criteria** and **what is out of scope**. That pair is
the whole of `kit:start-ticket`'s qualification test — an issue missing either
falls back to `/kit:design` when it's picked up, which is exactly the round trip
this command exists to prevent. Write outcomes in domain vocabulary and keep
substrate out of them; `kit:writing-tickets` owns that.

Say in the body that only the acceptance criteria are binding. Without it,
`kit:start-ticket` reads the whole body as settled and won't relitigate a
direction that was a guess.

**Write the blocking-edge marker.** Every ticket this command publishes gets
this line in its body, whether or not anything blocks it:

```
<!-- kit-blocked-by: 101,102 -->
```

Issue numbers only, comma-separated, no `#`. **A ticket with no blockers gets the
line with nothing after the colon** — `<!-- kit-blocked-by: -->`. `kit:to-tickets`
owns the format; follow it exactly, and write the prose "Blocked by" section
alongside it so a human reads the same thing the marker says.

The empty form is not a formality, and omitting it is the failure this step
exists to prevent. `/kit:ship-ticket` reads **absent** as "not part of an epic,
leave alone" — so a ticket with a perfect brief and the label still gets skipped,
silently, and looks startable the whole time. Present-and-empty is what says
"startable now".

Here is where the edges are known: you have just grilled scope and decided which
adjacent decisions fold into this ticket and which are their own. That is the
same conversation that establishes what has to land first. Any ticket you split
out during that pass is a candidate edge — put its number in the marker of
whatever now depends on it.

If the issue already carries a marker, reconcile rather than append: a second
line means two answers to one question, and nothing downstream picks a winner.
Say what you changed and why.

**The marker holds issue numbers and nothing else.** It is read mechanically —
`/kit:ship-ticket` satisfies it by checking that each number is closed — so a
blocker it cannot close is not expressible there. A credential that has not been
issued, a vendor account in review, a change landing in another repo, a decision
you have not made: those go to the `kit-blocked` label below, with the reason in
the prose "Blocked by" section next to the marker. Do not smuggle them into the
marker as free text; it is parsed, and a token that is not a number either breaks
the check or is silently dropped.

**Apply the AFK-ready label** — `ready-for-agent` in the canonical vocabulary,
or the project's own mapping where it differs.

Be clear with the user about what the label does, because it is narrower than
"this ticket is vetted" and says less than its name suggests:

- It is *not* what makes the issue qualify for `kit:start-ticket`. That reads
  the body; the label is corroboration and a staleness date.
- It is *not* a claim that the brief is settled. The ticket's kind answers that,
  and `/kit:ship-ticket unattended` designs the ticket itself where the kind allows.
- Its one behavioral effect is that **a `/kit:ship-ticket` sweep will select this ticket**
  — it is the filter deciding what gets picked up, without anyone naming the
  issue.

So the label answers one question and only one: **who writes the code?** An agent
gets `ready-for-agent`; a human gets `ready-for-human`. Everything else a reader
might expect it to mean is carried by another label.

**Withholding is not a lever.** The pull to withhold is always the same — the
ticket is not quite ready in some way — and the answer is always the same: label
it and let the mechanism refuse it, out loud, with the reason attached. An
unlabelled ticket is invisible to the sweep no matter what has since landed, and
becomes startable only through a re-triage nobody scheduled. Three shapes of
"not quite ready", none of them a withhold:

- **A blocking dependency.** A `/kit:ship-ticket` sweep only picks up a ticket whose
  `kit-blocked-by` marker is fully closed, so the edge already holds it back.
  Record the edge in the marker, then label it — and it starts itself the moment
  its blocker merges.
- **An unsettled brief.** The design pass parks on it and says so. Any kind but
  `user-experience` means `/kit:ship-ticket unattended` designs the ticket rather
  than parking on a missing plan, and parks in-flight if the design itself cannot
  be settled; a `user-experience` kind parks for its kind. Either way the refusal
  is visible and carries its reason, which withholding does not.
- **An absent kind.** Also a park, for the same reason — acceptance nobody has
  characterised cannot be assumed assertable. Assign the kind in step 1; do not
  compensate for a missing one here.

**Everything else that stands in the way gets the label plus `kit-blocked`.**
The label still says an agent writes this one; what has changed is that the
world will not let it start yet. Two cases:

- The ticket waits on something no merge will clear — a credential, a vendor
  account, a change in another repo, a decision that is yours to make and does
  not touch the approach.
- The ticket is settled but names a step no agent should take alone: a data
  migration that must reconcile production, anything destructive, anything whose
  blast radius the acceptance criteria don't bound.

Both are `ready-for-agent` **and** `kit-blocked` — `gh issue edit <n> --add-label
kit-blocked` — with the reason written into the body's "Blocked by" section.
`/kit:ship-ticket` skips a `kit-blocked` ticket and reports it by name with that
reason, and never removes the label; clearing it is your statement that the thing
is actually cleared. The difference from withholding is that the ticket stays
visible and becomes startable the moment you drop one label, rather than needing
a re-triage nobody scheduled.

So the levers are not interchangeable, and only one of them is a refusal.
`ready-for-human` routes the work to a person. `kit-blocked` says the brief is
finished and the *world* is not ready. Neither is a comment on the brief — that
is the design pass's to make, in front of whoever is watching.

Say which of these applies rather than just declining. Confirm the label as its
own decision rather than folding it into the publish.

**Then ask two more questions, in the same breath.** First, is anything holding
the start?

```
Anything a human must clear before an agent starts this? (y/N)
```

Yes means `kit-blocked` and a line in "Blocked by" saying what and who clears it.
Same reason to ask it here as the hold below: the scope pass you just ran is what
surfaced the credential, the vendor, or the migration, and this is the last
moment that context is in front of you. Default to no.

**Second: will the PR need holding?**

```
Hold the PR for in-app verification before it merges? (y/N)
```

If yes, put `kit-hold` on the **issue** — `gh issue edit <n> --add-label
kit-hold`. `/kit:new-pull-request` transcribes it onto the PR it opens, so the
hold is in place from the moment the PR exists.

Ask it here because **here is where the answer is known**. You have just decided
this is safe for an agent to start alone; whether the result needs walking in the
running app before it merges is the same judgment, made with the same context in
front of you. The alternative is finding out later: the agent opens a PR, the CI
gate fires as soon as CI finishes, and you are racing a workflow run to label
something you already knew would need it.

**Ask it of every kind, and never infer it from one.** A `user-experience`
ticket is the obvious candidate for a hold and still often does not need one —
it may be a dependency inside a suite, with nothing rendered to walk yet. A
`technical-debt` ticket can need one, when the refactor lands under a view whose
behavior no test pins. Kind says who must be present at the design; this question
asks what the finished PR needs. They are different judgements and the second is
the user's.

**Default to no, and keep the question cheap.** Most tickets do not need a hold —
the reviewers and the acceptance criteria are the check, and a PR that merges
clean is the normal outcome. A prompt that demands real thought every time is one
people learn to dismiss without reading, which costs you the few that mattered.
Bare Enter means no hold.

Say yes when the acceptance criteria describe something you have to *see* — a
rendered view, an interaction, a migration's effect on real data — rather than
something a test asserts. That is the case `kit-hold` was built for, and it is
usually obvious from the criteria you just wrote.

## Staleness

An agent-ready issue is designed to sit in the queue, so its brief ages in a way
a plan written an hour ago does not. Nothing here can prevent that, and
`kit:start-ticket` already re-verifies anchors before implementing. Don't add a
freshness claim to the body that will itself go stale — the label's application
date is the timestamp, and that command knows to read it.

## Never

- Make implementation changes. This command designs and publishes; it writes no code.
- Apply the agent-ready label to more than one issue without individual approval.
- Widen a ticket's scope without telling the user it got wider.
- Skip step 3's grilling because step 2 already grilled something.
- Remove `kit-blocked` from an issue. Applying it is a decision the user confirms;
  clearing it is their statement that the thing was actually cleared, and you
  cannot verify what it was waiting on. Re-triaging a blocked ticket does not
  clear it either.
