---
name: startable-tickets
description: Decide which open tickets an agent may pick up on its own — the candidate query, the five conditions, and what the epic, kit-blocked, and kit-blocked-by markers mean. Use when sweeping a backlog for work to start, or listing what a sweep would take.
---

# Startable Tickets

**Startable** means an agent may pick this ticket up without anyone naming it.
One rule, because two copies drift and the first symptom is a list promising a
ticket the sweep then refuses.

**This is shared mechanism, not an entry point.** It classifies a candidate set
and hands back both halves. What to do with either half belongs to the caller:
`/kit:ship-ticket` takes the lowest startable number and reports the rest with
their reasons; `/kit:list` prints the startable half and discards the reasons.

**Arguments:** optionally a label to narrow the candidates by. With none, the
whole backlog.

## Step 1 — Gather the candidates

```
gh issue list --state open --label ready-for-agent [--label <given>] --json number,title,body,labels
```

`ready-for-agent` is the canonical spelling of the project's AFK-ready triage
label; read the project's own mapping where it has one.

**A caller narrowing by a label that does not exist gets an error from `gh`, not
an empty list.** Pass that distinction back — a label nobody created and a label
holding nothing startable are different answers, and only the first is a typo.

## Step 2 — Apply the five conditions

A ticket is **startable** when all of these hold:

1. Its body contains `<!-- kit-blocked-by: ... -->`. No marker means it was not
   filed as part of an epic — leave it alone. A sweep never picks up an arbitrary
   `ready-for-agent` ticket, only one whose author declared its edges.
2. Every issue number in the marker is **closed**. `/kit:new-pull-request` writes
   `Closes #<issue>`, so a merged PR closes its ticket — a closed blocker means
   the work landed on `main`. An empty marker is trivially satisfied.
3. It does **not** carry the `epic` label.
4. It does **not** carry the `kit-blocked` label.
5. No open PR or live worktree already exists for it — it has not been started.

**The label requirement in step 1 is deliberate, and is not the one
`kit:start-ticket` `plan-implementation` relaxed.** There a human has already
named the issue, so the label merely corroborates a body you can read, and
demanding it withholds work over a missing sticker. Here the label is the filter
deciding what gets picked up at all, and dropping it would mean starting whatever
happens to be open. Do not harmonize the two.

## Step 3 — Hand back both halves

The startable tickets, and every excluded one with the condition that excluded
it. A caller that wants only the first half asks for only the first half; the
reasons cost nothing to carry and are the whole content of `/kit:ship-ticket`'s
report when nothing is startable.

Three exclusions carry a reason worth quoting rather than a condition number:

**`kit-blocked` — waiting on a person, not a merge.** The marker in condition 2
carries one kind of edge: another ticket, cleared when a PR merges and closes it.
A machine clears it, which is why a sweep can read it and act. Plenty of what
holds a ticket back is not that shape — a credential that has not been issued, a
vendor account still in review, a change landing in another repo, a decision
nobody has made, a migration whose production reconcile is unwritten. None of
those close an issue, so none can be written as a number, and a ticket waiting on
one is fully designed and correctly labelled `ready-for-agent`.

`kit-blocked` on the **issue** is how that is said. It is the start-side twin of
`kit-hold`: `kit-hold` stops a finished PR from merging, `kit-blocked` stops a
ready ticket from being started. Both are a label read rather than weighed, and
both are a human's to write. Create it once per repo with
`gh label create kit-blocked`, or from the UI.

The reason lives in the issue body's `## Blocked by` section, alongside the
marker. Read it and carry it. A `kit-blocked` ticket with no reason in its body
is worth saying so about — a block nobody can read is indistinguishable from one
left on by accident.

**`epic` — a container, not a slice.** An epic is the parent the slices were cut
from, with no implementation of its own, so there is no state of the world in
which starting one is right. That is what separates it from `kit-blocked`, where
the thing being waited on may genuinely have cleared. The label is a claim about
the ticket's kind, fixed when the ticket is filed — by a person, or by a
`kit:improve-codebase-architecture` run over the children it cut. Read that claim
rather than adjudicating it. Create the label once per repo with
`gh label create epic`.

**No marker — condition 1, and the one exclusion a caller should name out loud.**
A ticket carrying the AFK-ready label but no `kit-blocked-by` line is the one
failure this rule cannot distinguish from a deliberate omission. Someone briefed
and labelled that ticket expecting it to be picked up, and from the outside being
left alone looks identical to being ignored for no reason. Report those
separately, and leave the epics out of that list — every remedy for a missing
marker makes the ticket startable, which is exactly what must not happen to a
container.

## Never write what you read

`epic`, `kit-blocked`, and the `kit-blocked-by` marker are a human's statements
about the ticket. Report what they say. Applying one, removing one, or writing an
empty marker onto a ticket that lacks one is this rule granting itself the
permission the marker exists to give.
