---
name: domain-modeling
description: Build and sharpen a project's domain model. Use when discussing codebase terminology, writing or editing a CONTEXT.md, or recording or editing an ADR.
license: MIT — Copyright (c) 2026 Matt Pocock (LICENSE); changes Copyright (c) 2026 Ron Ranauro, https://github.com/rranauro/claude-kit
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline: challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise. (Merely *reading* `CONTEXT.md` for vocabulary is not this skill: that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

Three callers reach it, each at the point where the model actually changes:
`/kit:architect` when the topic turns on what a thing *is* rather than how it
works; `/kit:design` once a choice is confirmed, for the concept it names and
the alternatives it rejected; and `kit:improve-codebase-architecture` for the
same two artifacts a scan leaves behind. It never runs on its own during
unrelated work — a session touching the code is not a session changing the
model.

## File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily: only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.

**Those are the defaults, not fixed paths.** A project can move the single-context
glossary and the ADR directory off the root, and `kit:working-files` resolves
where each one is — read, create and number them there. Every `CONTEXT.md` and
`docs/adr/` in this skill and its two formats means that resolved location. A
`CONTEXT-MAP.md` layout is not covered; its contexts live where the map says.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y. Which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account': do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible. Which is right?"

### Update CONTEXT.md inline

When a term is resolved, capture it right there. Don't batch these up: capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

**Capture is not always a write.** Write the entry into `CONTEXT.md` only in the
checkout of the ticket that will land it — its worktree, on its own branch. Anywhere
else — the default branch, another ticket's branch — record the settled wording
verbatim in the artifact your caller is producing, and leave the file alone; the
implementer of that ticket writes the entry from it. An edit left in a checkout no
ticket owns ships with nobody's PR, and every session that starts from that
checkout inherits vocabulary nobody reviewed. The same holds for an ADR.

Ask git which branch the checkout is on, once per session, rather than assuming;
a session is on the default branch far more often than in a ticket's worktree.

`CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse**: the cost of changing your mind later is meaningful
2. **Surprising without context**: a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off**: there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).
