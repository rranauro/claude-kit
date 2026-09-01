---
name: writing-tickets
description: Draft lean GitHub issues that state the problem and the decision without freezing an implementation. Use when filing an issue or ticket, or when another skill needs the ticket format.
---

# Writing Tickets

A ticket is a handoff to someone who will re-explore the current codebase before
they start. Write for that reader.

## Keep tickets lean

Capture the *decision* and the *why* — the agreed direction at the level of
intent — not a file-by-file implementation plan. Do NOT freeze file lists, line
numbers, or step-by-step instructions into the ticket.

Do NOT freeze the **implementation substrate** either: the data structure to
inspect, the input types, or a class shape like "a value object over the
before/after HTML pair." Substrate choices read as settled decisions but are
usually guesses made without the code open, and once written down they reach the
implementer with an authority they never earned — `kit:start-ticket` tells them not
to relitigate the plan's reasoning. Say what must be true, not what to build it
out of.

## State outcomes in domain vocabulary, not wire vocabulary

An acceptance criterion naming an HTML attribute, a JSON key, or a column header
silently picks that serialized form as the thing the implementer will go
inspect. Name the domain concept and let them find the representation the code
already uses.

> "Output `data-field` names are a superset of the input's" sends someone off to
> parse HTML. "The redesigned component must still declare every content field
> and collection the original declared" sends them to the schema the app already
> hydrates.

Same invariant, and only one of them costs a redundant parser. Frozen detail
rots as the repo drifts and becomes noise that has to be decluttered before real
work can start. A short ticket that survives is worth more than an exhaustive
one that misleads.

## Only the acceptance criteria are binding

Everything else in the ticket — the direction, the key decisions, whatever
context got written down — is the best guess at the time of writing, by someone
who did not have the code open. A downstream plan may supersede it freely, and
doing so is neither a scope change nor a conflict. A plan that satisfies the
criteria by another route has not violated the ticket.

Say this explicitly when the ticket carries any implementation detail at all.
Without it, `kit:start-ticket` reads the whole body as settled and will not
relitigate a guess that never earned that authority.

Revisit an acceptance criterion only when the *observable outcome* itself has to
change. Rewording one because the implementation went differently is how a
ticket stops describing anything.

## A criterion is a fence, not a route

Write each criterion with a **consumer** as its subject — the caller, the user,
the neighbouring system — and say what it must observe. A criterion whose
subject is the code ("the section markers are answered by the HTML layer")
describes the fix in the grammar of an outcome, and exactly one route satisfies
it. That contradicts the rule above: a plan meeting the criteria another way has
not violated the ticket, so a criterion only one plan can meet is not a
criterion.

Two tests, both cheap:

- Could the implementer satisfy this and still have built the wrong thing? The
  fence is too low.
- Could they satisfy it *only* by making the change already in your head? It is
  a route. Move it into the problem statement, where it is explicitly
  non-binding.

A ticket born from a diagnosis is where this goes wrong, because each finding
looks like a criterion waiting to be written. It is not. For a refactor the
fence is almost always **behavior preservation** — every consumer still receives
what it received, by whatever path — and one sentence naming those consumers and
the directions that must hold is often the entire binding set. A diagnosis
ticket carrying seven criteria has usually copied its findings across the line.

## Slice a body of work vertically

When one conversation produces several tickets, the split is a design decision,
not clerical work — and the wrong split is what makes a sequence of PRs
unreviewable.

**Each ticket cuts a narrow but complete path through every layer it touches.**
Storage through interface, with its tests. A finished slice is demoable or
verifiable on its own. Do not file "the models," then "the endpoints," then "the
screens" — nothing is verifiable until the last one lands, and the reviewer of
the first has no way to tell whether it was right.

**Prefactoring is its own slice, filed first.** Make the change easy, then make
the easy change — as two tickets, so the mechanical move is reviewable without
the behavior change buried inside it.

**Wide mechanical refactors are the exception.** Renaming a column, retyping a
shared symbol — anything whose blast radius fans across the codebase can't be
made vertical without touching everything at once. Sequence those expand →
migrate in batches → contract, each phase its own ticket, and say so rather than
forcing a slice that doesn't exist.

**Give each ticket its dependencies.** Which tickets must finish before this one
can start. A ticket with none can start immediately, and that's the ordering the
set actually has. For a chain, base each PR on its blocker's branch — GitHub
retargets automatically when the blocker merges.

This skill records those dependencies as prose only. The machine-readable form
the unattended commands read is `kit:to-tickets`' — reach for it when a whole set
is being filed at once.

**Title them in the project's own vocabulary** — the words the codebase and its
docs already use, not coined jargon. A term that turns out to be fuzzy is a
question for the conversation that produced these tickets, not something to
settle by picking a name here.

## Format

**Use the project's ticket format if it has one.** Check, in order:
`.github/ISSUE_TEMPLATE/`, a ticket/issue convention in `CLAUDE.md` or
`CONTRIBUTING.md`, and failing those, the last few issues on the repo
(`gh issue list` → `gh issue view`) to infer the house style — sections, labels,
and whether closing keywords are expected. Match it.

The sections below are the fallback when the project has no format of its own.
The leanness rules above apply either way: whatever the template's headings, do
not fill them with file lists or substrate choices.

```
Title: [concise, actionable title]
Labels: [relevant labels]
---
## Problem / Motivation
[Why this change is needed — a few sentences]

## Proposed Approach
[The agreed direction at the level of intent and key decisions. NOT a file-by-file plan.]

## Acceptance Criteria
- [ ] [Specific, verifiable outcomes]

## Dependencies
[Other issues that must come first, or that this unblocks]
```

Present the draft for approval BEFORE creating anything. Ask the user to confirm
before running `gh issue create`. Create issues one at a time so the user can
review each.
