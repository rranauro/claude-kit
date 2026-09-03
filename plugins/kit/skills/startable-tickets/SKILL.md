---
name: startable-tickets
description: Decide which open tickets an agent may pick up unbidden — the candidate query, the five conditions, and the batched lookups that answer them. Use when sweeping a backlog for work to start, or listing what a sweep would take.
---

# Startable Tickets

**Startable** means an agent may pick this ticket up without anyone naming it.
One rule, because two copies drift and the first symptom is a list promising a
ticket the sweep then refuses.

**This is shared mechanism, not an entry point.** It classifies a candidate set
and hands back both halves — the startable tickets, and every excluded one with
the condition that excluded it. What to do with either half belongs to the
caller.

`CONTEXT.md` owns what `epic`, `kit-blocked`, and `kit-blocked-by` mean. Read
them there; this skill states only how they are read.

**Arguments:** optionally a label to narrow the candidates by. With none, the
whole backlog.

## Step 1 — Gather the candidates

```
gh issue list --state open --label ready-for-agent [--label <given>] \
  --limit 200 --json number,title,body,labels
```

`ready-for-agent` is the canonical spelling of the project's AFK-ready triage
label; read the project's own mapping where it has one.

**The explicit `--limit` is load-bearing.** `gh issue list` defaults to 30,
newest first, so the tickets it drops are the oldest — the lowest numbers, which
is exactly what a sweep is defined to take. The truncation is silent: the sweep
reports a startable ticket that is not the earliest slice, or reports nothing
startable while an eligible older ticket sits off the end of the page. Raise the
limit or page rather than trusting the default.

**A label that does not exist makes `gh` fail; a label holding nothing startable
returns rows that all get excluded.** Different answers, and only the first is a
typo. Pass the distinction back rather than flattening both to "nothing".

## Step 2 — Resolve the two lookups, once for the whole set

Conditions 1, 3, and 4 are answerable from the bodies and labels Step 1 already
returned. The other two need data, and both are set-wide questions — asking them
per candidate is where a sweep's round trips go.

```
gh pr list --state open --json number,title,headRefName,body --limit 200
git worktree list
```

Those two answer condition 5 for every candidate at once.

For condition 2, union the issue numbers across every candidate's marker,
dedupe, and resolve them in **one** query. The candidates are by construction the
slices of one epic, so the same blocker recurs across markers — a ten-ticket epic
with a shared prerequisite otherwise queries that one issue ten times.

## Step 3 — Apply the five conditions

A ticket is **startable** when all of these hold:

1. Its body contains `<!-- kit-blocked-by: ... -->`. No marker means it was not
   filed as part of an epic — leave it alone. A sweep never picks up an arbitrary
   `ready-for-agent` ticket, only one whose author declared its edges.
2. Every issue number in the marker is **closed**. `/kit:new-pull-request` writes
   `Closes #<issue>`, so a merged PR closes its ticket — a closed blocker means
   the work landed on `main`. An empty marker is trivially satisfied.
3. It does **not** carry the `epic` label.
4. It does **not** carry the `kit-blocked` label.
5. No open PR and no live worktree names it — it has not been started.

**The label requirement in Step 1 is deliberate, and is not the one
`kit:start-ticket` `plan-implementation` relaxed.** There a human has already
named the issue, so the label merely corroborates a body you can read, and
demanding it withholds work over a missing sticker. Here the label is the filter
deciding what gets picked up at all, and dropping it would mean starting whatever
happens to be open. Do not harmonize the two.

## Step 4 — Hand back both halves

Two exclusions carry more than a condition number:

- **`kit-blocked`** — the reason lives in the issue body's `## Blocked by`
  section, alongside the marker. Carry it. A `kit-blocked` ticket with no reason
  there is worth flagging: a block nobody can read is indistinguishable from one
  left on by accident.
- **A missing marker** — condition 1, and the exclusion a caller should keep
  apart from the rest. Someone briefed and labelled that ticket expecting it to
  be picked up, and from the outside being left alone looks identical to being
  ignored for no reason. Keep the epics out of that group: every remedy for a
  missing marker makes the ticket startable, which is what must not happen to a
  container.

## Never write what you read

Report what the labels and the marker say. Applying one, removing one, or
writing an empty marker onto a ticket that lacks one is this rule granting itself
the permission the marker exists to give. `kit:park` is the one place
`kit-blocked` is written.
