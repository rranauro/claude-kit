---
name: observations
description: Record what a pass learned while running as a checkable claim in a store outside the repo, instead of asking the user about it — the record shape, where the store lives, and the triage that clears it down. Use when a pass closes holding something the ticket did not ask for, or when a command needs the observation format.
---

# Observations

A pass that processes a ticket end-to-end finishes holding something the ticket
did not ask for — a seam in the process, a rule that did not fire, a premise that
arrived unverified. Today the only destination is the user's attention at the
moment they are finishing something else, so a real finding is acknowledged and
lost.

**An observation goes to a store instead.** One record, appended by the pass that
saw it, reviewed later in its own pass. It stops nothing and demands nobody,
which is what separates it from `kit:park`: a park stops work and requires a
person before anything continues; an observation requires only that the drawer
gets opened eventually.

## The record

A record is **a claim the repository can contradict, the command that tests it,
and that command's answer at the time.**

That pair is the whole design. Triage becomes *re-run and diff* rather than a
judgement call: a record whose witness has moved was either acted on or was
wrong, and it dies without anyone adjudicating it.

| field | what it carries |
|---|---|
| `v`, `id`, `at`, `by` | schema version, slug, date, the pass that wrote it |
| `ctx` | repo, issue, branch, PR — what the pass was processing |
| `claim` | the observation stated so the repo can contradict it |
| `check` | a cheap, local, read-only command that tests the claim |
| `witness` | that command's output when the record was written |
| `surfaced` | the thread that exposed it — the part that cannot be re-derived |
| `action` | the destination, not a plan: this backlog, the kit, a doc, a prompt-file edit |

**`claim` is forced into checkable form, and there is no second free-text
summary.** Two summaries of one observation drift, and the checkable one is the
one that has to survive. The cost is nuance — *"the Parked list has no durable
home"* becomes a statement about a named file — and it is worth paying.

**`check` is cheap, local and read-only.** No network, no test suite. Triage
re-runs every record's check, once per row; unconstrained, opening the drawer
fires a `gh` call or a suite run per entry and becomes something you schedule
instead of something you open. Where only the suite could falsify a claim, record
it against the file or symbol the suite would touch. A weak check that runs beats
a strong one that is skipped.

**`surfaced` is the expensive field.** Everything else can be re-derived from the
code; what the pass was doing when this became visible cannot. Write the thread,
not the topic.

## Writing one

```bash
plugins/kit/scripts/observe.sh \
  --by "kit:grilling" \
  --claim "<what the repo can contradict>" \
  --check "<the command that tests it>" \
  --surfaced "<the thread that exposed it>" \
  --action "<where this should end up>" \
  [--issue <n>] [--pr <n>]
```

The script runs the check itself and captures its own witness, so the two cannot
disagree. It also resolves the store, writes the exclude rule once, and builds
the JSON — a record is one line, and `witness` and `surfaced` routinely carry
newlines and quotes.

**Report the line it prints.** It names the claim, the slug, and how many records
the store now holds. That single line is both *you can tell this was recorded*
and *the drawer is this full*, and nothing counts the store on a schedule — so
the count reaching a reader at all depends on a producing pass passing it on.

**One observation per thing observed.** Three seams in one pass are three
records, each with its own check. A record carrying a list has no witness that
can move.

## Where the store lives

`.claude/observations.jsonl` at the **main checkout**, outside version control.
`observe.sh` resolves it; why it is there rather than on the issue is
`docs/adr/0005-observations-are-stored-outside-the-repo.md`.

The consequence a producer has to act on: **a pass whose checkout is discarded
records nothing that survives**, so on a runner the durable half is `kit-pinned`
on the PR. `docs/tending-on-a-runner.md` owns that case.

## What is not an observation

- **A park.** A park names a decision a person must make before the pass can
  continue.
- **A finding the pass can act on now.** Acting on it is cheaper than recording
  it, and a record of work already done is a record that will be triaged twice.
- **A ticket.** Where the problem and the desired outcome are both already clear,
  `kit:writing-tickets` applies and the backlog is the right drawer. An
  observation is for what is real but not yet stateable that way.

## Triage

The store is reviewed in its own pass, never inside the pass that wrote to it.
`/kit:observe triage` is the entry point; this is the protocol it runs.

**1 · Re-run every check.** `observe.sh recheck` does it in one pass and reports
each record as holding or moved.

**2 · Bin each record by what the recheck said**, since that is evidence rather
than a judgement:

- **Moved** — the repository no longer gives the answer the record was written
  against. Read the claim once against what the check now says. Either the
  observation was acted on, or it was wrong; both are a drop. Say which in one
  line, so a re-observation of the same thing later is not a surprise.
- **Holds, and the claim still reads as real** — it goes to its `action`. File it
  with `kit:writing-tickets`, carrying `surfaced` across verbatim; or make the
  edit now if it is small and located.
- **Holds, and the user decides against it** — a drop, and the useful kind. The
  claim was checkable and still true, and it is still not worth doing.

**3 · Clear down what was binned**: `observe.sh drop <slug> ...`. It rewrites the
store atomically; every other write is a single-line append.

**Nothing survives triage untouched.** A record left in place with a fresher read
on it is a stale record, and the drawer exists because the last one filled up.

**The user decides what survives and where it goes** — every bin above is
presented, never applied. Triage clears down local state a person has not seen,
and a pass that drops its own records is the auto-memory problem this store was
built to avoid.

**A line that will not parse is skipped and reported.** Nothing validates the
store on write except the script, so one corrupt record must not strand the
drawer.
