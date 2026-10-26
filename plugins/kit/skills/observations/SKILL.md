---
name: observations
description: Record what a pass learned while running as a checkable claim in a store outside the repo, instead of asking the user about it — the record shape, where the store lives, and the triage that clears it down. Use when a pass closes holding something the ticket did not ask for, or when a command needs the observation format.
license: MIT — Copyright (c) 2026 Ron Ranauro, https://github.com/rranauro/claude-kit
---

# Observations

A pass that processes a ticket end-to-end finishes holding something the ticket
did not ask for — a seam in the process, a rule that did not fire, a premise that
arrived unverified, a defect outside its scope. Today the only destination is
the user's attention at the moment they are finishing something else, so a real
finding is acknowledged and lost.

**An observation goes to a store instead.** One record, appended by the pass that
saw it, reviewed later in its own pass. It stops nothing and demands nobody,
which is what separates it from `kit:park`: a park stops work and requires a
person before anything continues; an observation requires only that the drawer
gets opened eventually — and every record says what it waits on, so it can be
drained without re-deriving what it needs.

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
| `who` | who gets a wrong result: a visitor, an owner, an operator, an agent |
| `affected` | what they do, and what they get instead of what they expect |
| `check` | a cheap, local, read-only command that tests the claim |
| `witness` | that command's output when the record was written |
| `surfaced` | the thread that exposed it — the part that cannot be re-derived |
| `action` | what the ticket is, or the question the owner decides — never just "this backlog" |
| `waiting` | `ticket` — ready to file — or `owner` — a call only the owner can make |
| `decision` | the call the recording pass made, where it made one |

**`claim` is forced into checkable form, and there is no second free-text
summary.** Two summaries of one observation drift, and the checkable one is the
one that has to survive. The cost is nuance — *"the Parked list has no durable
home"* becomes a statement about a named file — and it is worth paying.

**`check` prints something that differs between a true and a false claim.** An
empty answer is accepted, since an absence is a valid witness, but prefer one
that prints either way: `grep -c`, or `... && echo yes || echo no`, over
`grep -n` of a line you expect to move. Line-number prefixes are ignored at
recheck, but only text is compared.

**`check` runs under a plain `bash -c`, with no profile and no session.** A
command that resolves only in your shell — Claude Code's `rg` is a function from
its snapshot — does not exist there, so the record is refused and the message
names the command. Write it with `grep -rn` instead. The script needs bash 4 or
later on `PATH` to tell a missing command from one that ran, and refuses to run a
check without it. Write paths relative to the repo root; a path under `.claude/worktrees/` is
refused, since that directory is gone once the ticket merges.

**`check` is cheap, local and read-only.** No network, no test suite. Triage
re-runs every record's check, once per row; unconstrained, opening the drawer
fires a `gh` call or a suite run per entry and becomes something you schedule
instead of something you open. Where only the suite could falsify a claim, record
it against the file or symbol the suite would touch. A weak check that runs beats
a strong one that is skipped.

**`who` and `affected` are the finding stated as someone's wrong result.** Name
the role, then what they do and what they get instead of what they expect. An
agent counts: a pass misled by a doc that describes behaviour no code implements
gets a wrong result as surely as a visitor does. Nobody is an answer too —
*What is not an observation* says what it does.

**`waiting` is `owner` only for a call the recording pass may not make — a
product call, or one that contradicts an ADR — or one its code cannot settle.**
Any other call is the recording pass's to make: make it, write it into
`decision`, and record `ticket`. Deferring a call an agent could make leaves the
record waiting on nobody, since the owner reads it as already decided and the
next agent reads it as not theirs. An `owner` record's `action` states the
question in `kit:asking-a-human`'s register, so the owner can answer it without
the session. The script refuses a
record with no `waiting`, and an `action` naming only the backlog.

**`surfaced` is the expensive field.** Everything else can be re-derived from the
code; what the pass was doing when this became visible cannot. Write the thread,
not the topic.

## Writing one

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/observe.sh \
  --by "kit:grilling" \
  --claim "<what the repo can contradict>" \
  --check "<the command that tests it>" \
  --surfaced "<the thread that exposed it>" \
  --action "<where this should end up>" \
  --who "<visitor | owner | operator | agent | nobody>" \
  --affected "<what they do, and what they get instead of what they expect>" \
  --waiting "<ticket | owner>" \
  [--decision "<the call this pass made>"] [--issue <n>] [--pr <n>]
```

The script runs the check itself and captures its own witness, so the two cannot
disagree. It also resolves the store, writes the exclude rule once, and builds
the JSON — a record is one line, and `witness` and `surfaced` routinely carry
newlines and quotes.

**Report the line it prints.** It names the claim, the slug, and how many records
the store now holds — or, for `--who nobody`, that the finding was dropped and
why. That single line is both *you can tell this was recorded*
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
records nothing that survives**, so a record that has to outlive a runner goes on
the PR instead. `docs/tending-on-a-runner.md` owns that case.

## What is not an observation

- **A park.** A park names a decision a person must make before the pass can
  continue.
- **A finding the pass can act on now.** Acting on it is cheaper than recording
  it, and a record of work already done is a record that will be triaged twice.
- **A finding that affects nobody.** A missing index on a 44-row table, a fix for
  a layout no theme uses, a log line nobody reads differently: each is true and
  each is re-checked at every triage, where it buries the findings someone pays
  for. Pass `--who nobody` with `--affected` saying why: the script writes
  nothing and prints the drop, which is the line to report.
- **A finding already stated where its reader looks** — the PR body, the
  issue's stored plan, or a `kit-pinned` comment, the review round's own summary
  included. A second copy is triaged twice and drifts from the first. **Unless
  the place it is stated can close before its reader gets there** — a PR that
  can merge unread — and the finding waits on the owner: then it is recorded
  too. `/kit:review-copilot` Step 7.5 is that case.

A ticket-shaped finding *is* an observation: record it `--waiting ticket`, with
its decision. Filing it directly would make every pass's close a network write
— `docs/adr/0008-the-observation-store-is-a-queue.md` says why that stays out.

## Triage

The store is reviewed in its own pass, never inside the pass that wrote to it.
`/kit:observe triage` is the entry point; this is the protocol it runs.

**1 · Re-run every check.** `${CLAUDE_PLUGIN_ROOT}/scripts/observe.sh recheck` does it in one pass and reports
each record as holding, moved, gone, or unrunnable. *Gone* means the path the check reads no
longer exists: the check can no longer answer, which is evidence about the check
and not the claim. Rewrite it against the file's new home, or drop the record.

`observe.sh rewitness <slug> ...` re-captures a record's witness from the main
checkout without touching its claim. Use it on records written before their
code merged, whose witness is empty or reflects the branch rather than main.

**2 · Bin each record by what the recheck said**, since that is evidence rather
than a judgement:

- **Moved** — the repository no longer gives the answer the record was written
  against. Read the claim once against what the check now says. Either the
  observation was acted on, or it was wrong; both are a drop. Say which in one
  line, so a re-observation of the same thing later is not a surprise.
- **Gone** — the check cannot answer. Rewrite it against the file's new home and
  re-record, or drop the record; either way the claim itself is unjudged.
- **Unrunnable** — the check calls a command its shell cannot find, named on the
  line below it. It never answered, so the claim is unjudged however long it has
  "held". Rewrite the check with commands a plain `bash -c` has and re-record, or
  drop the record.
- **Holds, and the claim still reads as real** — route it by `waiting`. A
  `ticket` record is filed with `kit:writing-tickets`, carrying `surfaced` and
  `decision` across verbatim, or made now if it is small and located. An `owner`
  record is put to the user as its `action`'s question, and their answer is the
  decision it is then filed with or dropped on. A record with no `waiting`
  predates the field: read its `action` and decide which it is.
  **Deciding one need not file it now.** `observe.sh set-waiting <slug> --waiting
  ticket --action <the ticket> --decision <the call>` marks it in place, keeping
  its date and so its place in the queue, and `ship-startable.sh --observations`
  files it unattended. A record from before `who` and `affected` takes both
  here too. Every rule an append enforces is enforced on the record as it will
  read.
- **Holds, and the user decides against it** — a drop, and the useful kind. The
  claim was checkable and still true, and it is still not worth doing.

**3 · Clear down what was binned**: `${CLAUDE_PLUGIN_ROOT}/scripts/observe.sh drop <slug> ...`. It rewrites the
store atomically, as `set-waiting` and `rewitness` do; every other write is a
single-line append.

**Nothing survives triage untouched.** A record left in place with a fresher read
on it is a stale record, and the drawer exists because the last one filled up.

**The user decides what survives and where it goes** — every bin above is
presented, never applied. Triage clears down local state a person has not seen,
and a pass that drops its own records is the auto-memory problem this store was
built to avoid.

**A runner may drain the `ticket` bin without you.** `ship-startable.sh
--observations` files, ships and drops one record at a time, taking only what
`observe.sh fileable` offers: a record waiting on a ticket whose check still
holds. That is a filing a person made in advance by opting in, not a triage, so
everything else here stays the owner's.

**A line that will not parse is skipped and reported.** Nothing validates the
store on write except the script, so one corrupt record must not strand the
drawer.
