---
name: to-tickets
description: Break a plan, spec, or the current conversation into a set of tracer-bullet tickets, each declaring its blocking edges, published to the configured tracker — edges as text in one file per ticket locally, or native blocking links on a real tracker.
disable-model-invocation: false
---

# To Tickets

Break a plan, spec, or conversation into a set of **tickets** — tracer-bullet vertical slices, each declaring the tickets that **block** it.

The issue tracker and triage label vocabulary should have been provided to you — run `/setup-matt-pocock-skills` if not.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a reference (a spec path, an issue number or URL) as an argument, fetch it and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Ticket titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

Look for opportunities to prefactor the code to make the implementation easier. "Make the change easy, then make the easy change."

### 3. Draft vertical slices

Break the work into **tracer bullet** tickets.

<vertical-slice-rules>

- Each slice cuts a narrow but COMPLETE path through every layer (schema, API, UI, tests) — vertical, NOT a horizontal slice of one layer
- A completed slice is demoable or verifiable on its own
- Each slice is sized to fit in a single fresh context window
- Any prefactoring should be done first

</vertical-slice-rules>

Give each ticket its **blocking edges** — the other tickets that must complete before it can start. A ticket with no blockers can start immediately.

**Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change — rename a column, retype a shared symbol — whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as **expand–contract**. First expand: add the new form beside the old so nothing breaks. Then migrate the call sites over in batches sized by blast radius (per package, per directory), each batch its own ticket blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally contract: delete the old form once no caller remains, in a ticket blocked by every migrate batch. When even the batches can't stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify ticket — green is promised only there.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each ticket, show:

- **Title**: short descriptive name
- **Blocked by**: which other tickets (if any) must complete first
- **What it delivers**: the end-to-end behaviour this ticket makes work

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the blocking edges correct — does each ticket only depend on tickets that genuinely gate it?
- Should any tickets be merged or split further?

Iterate until the user approves the breakdown.

### 5. Publish the tickets to the configured tracker

Publish the approved tickets. **How** depends on the tracker `/setup-matt-pocock-skills` configured — the tickets are the same either way, only the shape of the blocking edges changes:

- **Local files** → write one file per ticket under `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order (blockers first). Each file's "Blocked by" lists the numbers/titles it depends on. Use the per-ticket file template below — one ticket per file, never a single combined file.
- **A real issue tracker (GitHub, Linear, …)** → publish one issue per ticket in dependency order (blockers first) so each ticket's blocking edges can reference real identifiers. Use the platform's native blocking / sub-issue relationship where it has one; otherwise set each ticket's "Blocked by" to the blocking issues. Apply the `ready-for-agent` triage label unless instructed otherwise — the tickets are agent-grabbable by construction.

Work the **frontier**: any ticket whose blockers are all done. For a purely linear chain that means top to bottom.

Do NOT close or modify any parent issue.

<!-- FORK: everything below this marker is local. Keep it when porting upstream changes. -->

### 5a. Make the edges machine-readable

`/kit:start-next` picks up these tickets as their blockers merge, so it has to read the edges without a human having named the issue. Prose cannot carry that: a bare `#123` appears in ordinary issue text all the time, and a wrong match starts work whose dependency has not landed.

On a tracker, every ticket gets this line in its body, in addition to the prose "Blocked by" section:

```
<!-- kit-blocked-by: 101,102 -->
```

Issue numbers only, comma-separated, no `#`. **A ticket with no blockers gets the line with nothing after the colon** — `<!-- kit-blocked-by: -->`. Present-and-empty means "startable now"; absent means "not part of an epic, leave alone", and the loop cannot tell those apart if you omit it.

The marker is authoritative and the prose is for humans. Write both and keep them agreeing.

**Only ticket edges belong in the marker.** It is satisfied by each number being closed, so a blocker no merge can close — a credential, a vendor account, a change in another repo, a decision still open — has no expressible form here. Write that one in the prose "Blocked by" section and put `kit-blocked` on the issue; `/kit:start-next` skips a `kit-blocked` ticket and reports the prose reason. Never write a non-numeric token into the marker.

This needs two passes, since a ticket cannot cite a number that does not exist yet: create every issue first, collect the numbers, then edit each one to add its marker.

Before publishing, check the edges for a cycle. Two tickets that block each other can never start, and the loop will pass over them in silence rather than report anything.

### 5b. Give every ticket a scope boundary

Add an **Out of scope** section to each issue, alongside the acceptance criteria.

`/kit:start-ticket` `plan-implementation` accepts an issue in place of a stored plan only when it carries *both* testable acceptance criteria and stated scope boundaries. Criteria alone do not qualify it. A ticket missing the boundary falls through to `/kit:design` when an agent picks it up, which stalls the epic to ask a human for a decision this session already made.

It also does the job the section is named for: an agent implementing a narrow slice will otherwise fix adjacent things it notices, and the review round is a poor place to discover that.

<local-ticket-template>

# <NN> — <Ticket title>

**What to build:** the end-to-end behaviour this ticket makes work, from the user's perspective — not a layer-by-layer implementation list.

**Blocked by:** the numbers/titles of the tickets that gate this one, or "None — can start immediately".

**Status:** ready-for-agent

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2

</local-ticket-template>

<issue-template>

## Parent

A reference to the parent issue on the tracker (if the source was an existing issue, otherwise omit this section).

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective — not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Out of scope

- What this ticket deliberately does not change, especially adjacent problems an implementer will notice and want to fix. (Local addition — see 5b.)

## Blocked by

<!-- kit-blocked-by: 101,102 -->

- A reference to each blocking ticket, or "None — can start immediately".

</issue-template>

In either form, avoid specific file paths or code snippets — they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.
