---
name: triage-memory
description: Audit a project's auto-memory directory, bin every memory as stale, workflow, duplicate/conflicting, or unclassified, and clear it down with the user's per-bin approval. Use when memory has grown large, a memory turns out to be wrong, or the user asks to triage, prune, or audit memory.
---

# Triage Memory

Auto-memory is loaded into context on every session, so its cost is recurring
and its errors are silent — a memory that went stale keeps asserting itself with
the same confidence it had when it was true. Triage exists to pay that down.

The output is not a report. It is a **smaller memory directory** plus, where the
content deserved to survive, a durable home for it. Stopping at "here's what I
found" leaves the cost exactly where it was.

## Step 0 — Locate everything, then read all of it

Three inputs. Get all three before classifying anything.

**The memory directory.** `~/.claude/projects/<project-slug>/memory/`, holding
one fact per file plus a `MEMORY.md` index. The slug is the project path with
separators replaced by `-`.

**Every instruction file that auto-loads.** Walk from the repo root down to the
working directory: `CLAUDE.md`, `CLAUDE.local.md`, and any `<subdir>/.claude/CLAUDE.md`.
All of them, not just the nearest — the duplicate bin is defined against their
union, and a rule in the one you skipped still auto-loads.

**A local docs directory** for content worth keeping outside memory. If an
instruction file names one (a personal-reference or scratch-docs path), use it.
Otherwise ask, offering `.claude/docs/` as the fallback. Never invent a path in
a repo that already has a convention for this.

Then **read every memory file in full.** The `MEMORY.md` one-liners are written
to sell the memory, not to describe it; several of the sharpest classifications
only appear in the body. Note any file missing from `MEMORY.md` — orphans
accumulate there and are a finding in their own right.

## Step 1 — Verify before you bin

Classification is a research task, not a reading-comprehension task. The failure
mode is confidently binning from the memory's own text.

**Every "stale" call needs evidence from outside the memory.** Grep the symbol.
Stat the path. Run `git worktree list`. Check whether the ticket closed. A
memory asserting a class lives at `app/services/foo.rb` is not stale because it
feels old — it's stale when `find` says the file is at `app/actions/foo.rb`. Half
the value of a triage pass is the memories that *look* stale and verify clean,
and the other half is the ones that look fine and turn out to name paths that
moved.

**Every "duplicate" call needs the line it duplicates.** Quote it from the
instruction file. "This seems covered by CLAUDE.md" is a guess.

**Conflicts need a winner, and the memory can be the winner.** When a memory
contradicts an instruction file, establish which is true against the actual repo
*before* choosing an action. If the instruction file is the stale one, deleting
the memory destroys the correct fact and leaves the wrong one auto-loading every
session. That case is a fix to the instruction file — surface it as such and do
not bury it in a list of removals.

## Step 2 — Bin, in this order

Memories overlap bins. Assign each to exactly one, first match wins, so the more
destructive judgment never hides behind a softer one:

1. **Stale** — contradicted by the current repo, or a completed project, or
   re-derivable in one command. Anything the code answers better than the memory
   does. A memory describing method semantics, file layout, or schema shape is
   here by default: code drifts, memory doesn't.
2. **Duplicate or conflicting** — already stated by an auto-loading instruction
   file, or contradicting one. Duplication here is pure waste: the rule loads
   twice, in two wordings, and the wordings drift apart.
3. **Workflow** — a preference, correction, or convention the user established
   mid-flight. Not derivable from any file at the time it was written. Whether
   any of it is still worth keeping is the user's call in Step 3, not a
   judgment to make here.
4. **Unclassified** — everything else. Meeting notes, parked questions, inbox
   scraps, org process, project pointers. Some is valuable and simply isn't a
   rule; some is a note that outlived its week.

Report the tally per bin before proposing anything, and lead with any conflict
where the *instruction file* lost. That one changes what the user does next.

**Flag your own thin calls as you go.** Some classifications rest on real
evidence — a grep that came back empty, a closed ticket. Others rest on a read
of intent: whether a parked note is still live, whether a rule is personal or
team-wide. Mark the second kind. A triage pass that presents both with equal
confidence gets its weakest calls approved along with its strongest.

## Dry run

Invoked with `--dry-run`, stop here. Run Steps 0–2 and report; do not run Steps
3–6. Nothing is written, moved, or deleted — no removals, no `WORKFLOW.md`, no
archive, no `MEMORY.md` rewrite.

The dry run answers two questions, and a report that only answers the first is
just a preview:

**What do I get back?** Report the per-bin tally with each bin's share of the
memory directory — measure it, don't estimate from filenames. Context cost is
what makes triage worth doing, and "17 stale files, roughly a third of what
loads each session" is a decision; "17 stale files" is trivia.

**What would I lose?** Show the drafted `WORKFLOW.md` in full, not a summary of
it — the user is being asked to trade many memory files for one document, and
they can only judge that by reading the document. List the thin calls from
Step 2 together, with what would settle each.

Then write the classification to a **triage plan** in the local docs directory:
every file, its bin, the evidence, and the proposed action. A real run adopts
the plan instead of reclassifying from scratch, so arguing with the bins costs
one cheap recount rather than a full re-derivation. Re-verify anything the plan
marked thin before acting on it — the repo may have moved since.

Invite the user to challenge any bin. A recount is the expected next step, not a
failure of the first pass.

## Step 3 — Offer each bin separately

Four bins, four decisions, each with its own default. Present a bin as a table —
file, one-line claim, and for stale entries **the evidence that killed it** —
then ask once for the whole bin, taking exceptions by name. Do not ask a
separate question per file; a 60-file directory becomes an interrogation and the
user starts saying yes to everything, which is worse than not asking.

| Bin | Offer | Default |
|---|---|---|
| Stale | remove | Y |
| Workflow | delete all, or go item by item | ask, no default |
| Duplicate / conflicting | remove — *unless the memory won the conflict, then fix the instruction file* | Y |
| Unclassified | remove, or move to local docs | ask, no default |

**The workflow bin is the one bin you must not decide for the user.** Offer two
paths and let them pick:

- **Delete all** — the whole bin goes. Reach for this when the tooling has moved
  on: commands and skills absorb decisions over time, and a rule that was worth
  remembering when it had to be made by hand is dead weight once something else
  makes it. Whether that has happened is the user's read, not yours.
- **Item by item** — each memory is either deleted or saved into `WORKFLOW.md`.
  Present them one at a time with the rule stated in a line, so the choice is
  about the rule and not about the memory file wrapped around it.

Don't collapse these into a recommendation. The bin is large by nature, and a
default here decides most of the pass on the user's behalf.

The unclassified bin is the one to hold loosest. It's where a parked decision
and a stale scrap look identical from the outside, and the user is the only one
who knows which is which. Split it into "still live" and "outlived its week"
with your read of each, and let them correct you.

## Step 4 — Archive before deleting

**The memory directory is usually not a git repository.** Check before the first
deletion. If it isn't, there is no undo, and a triage pass that runs unattended
against 60 files is an irreversible bulk delete.

Write every removed memory — full content, not the summary — into one dated
archive file under the local docs directory before removing anything. One file,
appended per bin, so recovery is a single grep. Only then delete.

## Step 5 — WORKFLOW.md is rules, not an archive

Whatever the user chose to save goes into a `WORKFLOW.md` in the local docs
directory. Saving means **distillation**: a memory file is one fact wrapped in
the story of the session that produced it, and the story is what made it
expensive. Keep the rule and the *why* when the why is non-obvious. Drop the
ticket numbers, the session provenance, the dated narration of who said what —
that survives in the archive from Step 4 if anyone ever needs it.

Group by the phase of work the rule fires in — design, testing, review,
environment — not by the order the memories happened to be written. A reader
arrives with a task, not a timeline.

Merging into an existing `WORKFLOW.md`: read it first, fold each rule into the
section that already covers it, and reconcile rather than append. Two adjacent
sections stating the same rule differently is how this document rots into the
thing it replaced.

**Then check the rule doesn't belong in `CLAUDE.md` instead.** A rule that
applies to everyone working in the repo belongs in the shared instruction file;
`WORKFLOW.md` is for the personal layer. Getting this backwards recreates the
duplicate bin on the next pass.

### The point is that it doesn't auto-load

`WORKFLOW.md` earns its keep by being **read on demand**, not loaded every
session. That's the whole trade: memory pays context rent continuously, a doc
pays it only when the work touches it. So the instruction file gets a pointer —
one line naming the doc and when to read it — and never a copy of its contents.

If no such pointer exists yet, offer to add one. A `WORKFLOW.md` nothing points
at will not be read, and the rules in it are then worse off than they were in
memory.

## Step 6 — Wire the capture path before you delete

Deleting a rule is only safe if the situation it covered can re-teach it. Left
alone, the same correction gets rediscovered from scratch, and the pass that
cleaned memory up becomes the reason it refills with the same content.

So the instruction file also gets the capture rule: **when a decision comes up
that `WORKFLOW.md` covers, or that the user has to correct by hand, stop and
present it** — then ask where it belongs:

- **save as a memory** — it's situational and needs to be in context up front
- **update `WORKFLOW.md`** — it's a working rule, read when the work calls for it
- **update the instruction file** — it's a standing rule that must always apply

Three destinations, asked explicitly, so the choice is made once rather than
defaulting to memory every time. Offer to add this rule if it isn't there.

This is what makes "delete all" a safe answer in Step 3 rather than a lossy one:
the rules aren't being discarded, they're being moved to a channel that only
costs something when it's used.

## Step 7 — Close the loop

Rewrite `MEMORY.md` to match what survived. Every removal drops its index line;
every promotion is gone from the index entirely, not rewritten to point at
`WORKFLOW.md` — the index lists memories, and a pointer to a doc is a memory
that will need triaging later.

Then check the `[[wikilinks]]` in the surviving bodies. Removing memories
strands the links that pointed at them; a dangling link is tolerable as a marker
of something worth writing, but a link to a fact you just deleted as *wrong* is
worse than no link. Fix those.

Report what changed: counts per bin, what went into `WORKFLOW.md`, where the
archive landed, and — separately, at the top — any instruction file that needs
correcting because a memory beat it.

Delete the triage plan from the dry run once the real pass lands. It described a
directory that no longer exists, and left behind it becomes the next stale doc.
