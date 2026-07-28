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
implementer with an authority they never earned — `/start-ticket` tells them not
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
