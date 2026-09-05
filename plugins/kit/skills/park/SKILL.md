---
name: park
description: Stop an unattended pass at a question only a person can answer — the comment, the kit-blocked label, the worktree left in place, and the report line. Use whenever a command running without a user reaches a decision it may not make.
---

# Park

An unattended pass reaching a point where a human is genuinely needed. Nobody is
there. **Parking is what you do instead of asking** — the sanctioned refusal:
visible, reasoned, and resumable.

Every command that runs without a user reaches this. `/kit:ship-ticket
unattended` parks a ticket; `/kit:design unattended` parks a design;
`/kit:review-copilot unattended` parks a finding it may not decide. One stopping
shape, described once here, so the reports read alike and a reader never has to
work out which command invented which variant.

Parking is not a failure state, and it is not an error. It is the interrupt this
whole scheme exists to make rare and to make legible when it happens.

## The protocol

1. **Comment on the issue with the decision it needs**, not the symptom you hit.
   The reader is deciding, so give them the choice: *"the plan assumes
   `SiteAsset` owns the token table; it moved to `Css::TokenTable` in #1487 —
   does the approach still hold, or is the placement now different?"* A comment
   that only reports what went wrong makes the human re-derive the question
   before they can answer it.
2. **`gh issue edit <n> --add-label kit-blocked`**, with the reason written into
   the body's `## Blocked by` section. A park is the one occasion any command
   writes that label, and it is doing exactly what the label means: a human must
   clear it.
3. **Leave the worktree and any commits in place.** The next attempt resumes
   rather than rebuilds, and a parked ticket with its work-so-far on disk is
   worth more than a clean tree.
4. **Report it and stop working that ticket.** A park on one ticket does not stop
   a queue — the next one starts.

**Never remove `kit-blocked`.** Removing it is the human's statement that the
thing is actually cleared, and no command can verify what it was waiting on.

## The two failures

**Never guess to avoid parking.** A decision made silently to keep the run going
is the failure the gates existed to prevent, arriving faster and with a plausible
diff attached to it.

**Never park to avoid thinking.** A ticket parked over something the plan, the
acceptance criteria, or the project's own rules already answer wastes the
interrupt. The absence of a preference is not a park. A passing remark about
future work is not a park. "The user might want to weigh in" is not a test —
they might, always.

Most assertions resolve against the plan, the criteria, and the code. That is
the normal outcome, and it is the same outcome attended.

## Park once

**A park inside a command you invoked is your park.** If `/kit:design unattended`
parks, it has already commented and labelled. Carry its reason into your own
report and stop working the ticket — do not park it again. A second comment says
the same thing twice and leaves a reader dating two copies of one reason.

## It is already durable

Parking writes to GitHub. Nothing needs to remember it, no scheduled pass has to
re-derive it, and the label survives every session boundary. That is why a
`/loop` over an unattended command is safe: the queue's refusals accumulate
somewhere a person will see them.

## Reporting: split by what would clear it

Parks are the useful half of any unattended report — they are the operator's
queue. Listed as one block they read as one problem, and the cheapest of them
hides among the others. Split them by the act that clears each:

- **Waiting on an answer** — a decision inside the design, an either/or the axis
  scores level, a constraint the criteria do not bound. Someone reads the comment
  and replies.
- **Waiting on the world** — a credential, a vendor account, a change in another
  repo, a migration whose production reconcile is unwritten. Nothing about the
  ticket changes; something outside it has to.
- **Waiting on a label** — an absent kind, a missing marker. Seconds of work, and
  it should not be reported next to a decision that needs an afternoon.
- **Waiting on you specifically** — a `user-experience` ticket with no plan,
  parked because no unattended pass may derive one for that kind. It parks again
  on every firing until a human designs it, so name that act: designed attended,
  the ticket ships unattended thereafter like any other kind.
