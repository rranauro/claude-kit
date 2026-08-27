---
model: sonnet
---

Audit this project's auto-memory directory and clear it down to what still earns its context.

**Arguments:** `$ARGUMENTS` — optional. `--dry-run` classifies and reports without
writing or deleting anything. Bare, the command runs the full pass with your
approval at each bin.

Run the `kit:triage-memory` skill and follow it end to end.

Auto-memory loads on every session, so its cost recurs and its errors are silent
— a memory that went stale keeps asserting itself in the same confident voice it
had when it was true. This is the pass that pays that down.

---

## `--dry-run`

Stop after the skill's dry-run report. Nothing is written, moved, or deleted:
no removals, no `WORKFLOW.md`, no archive, no `MEMORY.md` rewrite. The only file
produced is the triage plan the skill writes for a later real run to adopt.

Reach for it when the question is **whether this is worth doing** — or when a
previous dry run's bins looked wrong and you want to see the recount after
arguing with them. Both are cheap; the real pass is not, because deleting from
a memory directory that isn't under git has no undo.

Two things make the dry run worth the tokens rather than just a preview:

- It shows **what you get back** — how much of the loaded context each bin
  accounts for, so "70 memories" becomes a number you can weigh against the
  work of reviewing them.
- It shows **what you'd lose** — the drafted `WORKFLOW.md` in full, and every
  removal that rests on thin evidence, called out rather than buried.

You can argue with any bin and ask for a recount. Nothing is committed until you
run the command without the flag.

---

## Without the flag

The skill asks per bin, defaults toward removal, and archives every removed
memory in full before deleting it. Two things it will not do quietly, both worth
knowing before you approve a bin:

- **A conflict can resolve against `CLAUDE.md`.** When a memory contradicts an
  instruction file and the *memory* is the one that matches the repo, deleting
  it destroys the correct fact and leaves the wrong one auto-loading forever.
  Those surface as instruction-file corrections at the top of the report, not as
  removals.
- **The workflow bin is yours to decide.** It's offered two ways — delete the
  whole bin, or go item by item choosing delete or save into `WORKFLOW.md` —
  with no default, because a default there decides most of the pass for you.
  Anything saved is rewritten as a rule: the session narration, ticket numbers,
  and dated provenance are dropped. The archive keeps the originals.

`WORKFLOW.md` is read on demand rather than auto-loaded, which is what makes
deleting from memory a move rather than a loss. The pass offers to wire both
halves of that into your instruction file: a pointer to the doc, and the rule
that a decision it covers — or one you have to correct by hand — stops and asks
whether it belongs in memory, in `WORKFLOW.md`, or in the instruction file
itself.

If a dry run already produced a triage plan, adopt it rather than reclassifying
from scratch — but re-verify anything it marked as thin evidence before acting
on it.
