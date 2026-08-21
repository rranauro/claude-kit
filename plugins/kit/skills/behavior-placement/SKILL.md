---
name: behavior-placement
description: Decide where behavior belongs — model, value object, or service — and whether the answer already exists. Use when designing new classes, reviewing a proposed service, refactoring, or when another skill needs the placement checks.
---

# Behavior Placement

Two checks to run before proposing any new class or refactor. An app is a
collection of models that own their data and behavior; services are the
residual, not the default. A project rule that says "default behavior to the
model" states the conclusion; this states how to reach it.

## Check 1 — where does the behavior live?

In priority order:

1. **A method or concern on the model that owns the data** — the default.
   Derived state, validation, state transitions, anything that primarily
   reads/writes one aggregate. Manage size with concerns, not by exporting
   behavior to a service that takes the model as an argument.
2. **A value/domain object instantiated from that data** (`Thing.new(record).query`)
   — when a cohesive bundle of derivations over one structure would swell the
   model. Name it for the concept (a noun). "It needs unit-testing without the
   DB" is NOT a reason to leave the model: a concern depending on two or three
   of its host's methods tests against a bare stub host just as cheaply. Narrow
   the dependency surface and the testability follows — don't buy it by moving
   the behavior somewhere it doesn't belong.
3. **A free-standing service** — only when the operation is genuinely external:
   coordinates multiple aggregates with no natural owner, adapts to the outside
   world (AI/HTTP/payments/storage), or is a multi-step workflow. Name it for
   the action/role; prefer an instance if it carries state.

Smells that model behavior has been misplaced into a service (stop and
reconsider): the signature is `Service.call(model:, …)` and the body mostly
reads from `model`; the name is an agent-noun verb (`-er`/`-or` — Resolver,
Swapper, Loader, Manager, Handler); it's a `self.call` that news-up an instance
and calls it once; `Service.call(model:, x:)` reads better as `model.verb(x:)`.

The same misplacement happens without a service in sight: a class method that
takes the record it operates on (`Model.do_thing(record)`) is an instance method
that never moved onto the instance. Reserve class level for what genuinely has
no receiver — scopes, finders, factories. If the first parameter is the
receiver, make it the receiver.

When refactoring: ask **"who owns this state?"** before "where does this file
go?" — layout follows ownership, and relocating a file to a nicer folder is the
lowest-value refactor. Put **delete / inline / fold-onto-a-model** on the
options list before "relocate." Find the existing seam (a concern already
hydrating related data) and extend it rather than reopening "service vs model."
Treat a prior "keep it a service" decision as an input to revisit when the user
reopens it, not a constraint.

When the answer really is a new class, propose its home rather than picking one:
name the nearest existing sibling of the same kind, say you'd put it beside that
one under that one's convention, and let the user confirm. Never open a new
top-level directory on your own — that's a claim the project has a category it
doesn't have yet, and it's the user's claim to make.

## Check 2 — what does the system already know?

Run this before proposing anything that computes a new answer out of existing
data. Search for a model, concern, or schema that already derives it. The reuse
that matters here is the *derivation*, not the class — a "look for an existing
equivalent" habit is about code, and it won't fire when the thing to reuse is an
answer.

Re-deriving from a serialized form (HTML, JSON, CSV headers) what the app
already hydrates forks the definition, and the two copies drift apart on the
first schema change. If a proposal starts by parsing something, ask what
populated that something and whether the populated form is still in reach.

## What to hand back

Both checks end in a proposal, not an action. State it in a few lines: what the
behavior is, where it should live and under what name, which check decided it,
and — if Check 2 found one — the existing derivation you'd reuse instead. Then
wait for the user to confirm before writing anything.

If the checks say the proposal on the table is misplaced, say so in the same
shape: where it is, where it belongs, and which smell gave it away.

## In a Rails codebase

The two checks above are language-neutral. Where the project is Rails, three
things sharpen them.

**The namespace carries the data; the child may carry the role.** `Csv`,
`Html`, `Api` name what kind of data is in play, and `Api::Request` or
`Csv::Editor` underneath is correct — an action name at the child level is not
the agent-noun smell. The smell is a top-level class named for an action with
no data structure above it.

**Counting settles what the checks leave to argument.** Construction taking
more than three arguments, or arguments from more than two aggregates, means an
unnamed structure is being assembled at every call site. Several class methods
threading the same argument through each other means that argument is the
`initialize` of the object that should exist. A class method whose first
parameter is the record is an instance method that never moved.
`kit:rails-codebase-design` holds the full set.

**Do not reach for dependency injection to answer a placement question.**
Neither check is satisfied by passing the database in, and "it would be easier
to test in isolation" is not a placement argument in either direction.

### Front-end modules

The same two checks apply to the JavaScript alongside. A Stimulus controller's
declared values and targets are its construction, so ownership is decided the
same way: state belongs to the module whose element holds it, and a module
querying or mutating DOM owned by another has taken on state it does not own —
move the behavior to the owner rather than reaching across.

Where the convention is that the server calculates state and hands the result
to the front end, Check 1 stops at the server. A module rendering what it was
given is correctly placed; do not propose relocating the calculation into it.

## Relation to other skills

`kit:rails-codebase-design` supplies the axis for *what shape* the result
should take — how `initialize` reads, whether methods chain, what to count when
they don't. This skill answers *whose* the behavior is. Run both when designing
a new class: placement first, shape second.
