---
model: opus
---

Walk this project's spec suite, prove which examples can be removed, and file
them as one ticket. It decides; it never deletes.

**Arguments:** none. The scan covers the whole suite, every time — expect tens of
minutes. Run it from the main checkout, against a clean tree.

**`kit:rails-load-bearing-specs` is the axis, and it owns the output contract
too.** What convicts, what does not, and what a pass says are all its. This
command finds the files, proves the candidates, and files the result.

**The one finding the axis does not own is subsumption**: reading cannot settle
it, and its only evidence is a run of two examples against the same mutations,
which is this command's.

---

## Step 1 · `enumerate` — Find the files and the runner

Read the project's spec directory and its test command from the project itself —
`CLAUDE.md` first, then the manifest, then CI config. Do not assume `spec/` or
`bundle exec rspec`; a wrong runner that errors is noise and one that silently
passes is worse.

Every `*_spec.rb` under that directory, excluding fixtures, factories, and
support. Report the count before fanning out — the run's cost is proportional to
it, and this is the last cheap moment to stop.

**Refuse to start against a dirty working tree.** Step 4 mutates tracked files
and reverts them with git, which cannot tell its own mutation from work you had
in progress. Say what is uncommitted and stop.

## Step 2 · `assess` — One subagent per file

Fan out through the **Agent tool**, one agent per spec file, in waves of about
eight. Each agent gets one file path and one instruction: apply
`kit:rails-load-bearing-specs` to it and return its output contract.

**One file per agent, never a batch.** An agent holding several files reports on
the aggregate, and the aggregate is what the axis's unit rule exists to prevent.

**A file whose agent fails is unassessed, not clean.** Carry it into Step 7 by
name. Silence about a file that errored reads identically to a file with nothing
in it, and the difference is what a suite sweep is trusted for.

## Step 3 · `rank` — Choose what to prove

Collate the returned lines and order convicted candidates by the axis's own
convictability: tautology, then dead code, then contradiction. **Take at most
twenty into Step 4.** The gate is expensive and the cap is what keeps a run
finite; say how many candidates it left behind.

Ranking exists only to choose that band. There is no report for it to order — if
the gate ever becomes cheap enough to run on everything, delete this step rather
than keeping it for shape.

**Fill any room left in the band with subsumption pairs** — last, because each
costs several mutations rather than one, and only when there is room, since a
full band would discard the search. Fan out one agent per spec directory, for
the directories holding at least two examples. A covering example may sit in
another file, so the unit is the directory: the files directly in it, not its
subdirectories. Each agent returns candidate pairs, one line each — the
candidate's `file:line`, the covering example's `file:line`, and the production
code both assertions reach. Reading only proposes a pair; Step 4 proves it. A
directory whose agent fails is unassessed for subsumption, and Step 7 says so.

## Step 4 · `prove` — Mutate, observe, revert

**This is not the axis's runtime witness, and it does not stand in for one.** A
runtime witness is production or CI observation over a window covering the path's
cadence; this is a local mutation run. A dead-code candidate is convicted by the
axis on a witness or not at all, and passing this gate never supplies one — the
gate answers whether an example fires, never whether a path is live.

What it buys is the executor's signal. Deleting a spec produces a diff that
cannot fail: the suite is green by construction afterwards. So the decider has to
hand down something that can.

For each candidate in the band, one at a time:

1. **Name the file you are about to change, before changing it.** If the run
   dies, that name is the only record of what to put back.
2. Mutate the production code the example's assertion reaches — a returned value
   inverted, a guard removed, an argument dropped. One change, in one file. For a
   tautology, that is the unit the enclosing `describe` names: an assertion that
   restates its own setup survives any mutation of it, and surviving is the
   proof. Where the assertion reaches no production code at all, that absence is
   itself the proof and there is nothing to mutate.
3. Run only the examples claiming to cover it. Named files and examples; never a
   directory and never the suite.
4. Record whether anything went red, and what.
5. **Revert with `git checkout -- <file>`**, never by editing the file back. A
   re-edit is a second guess at what the original said; a checkout is the
   original.
6. **Confirm with `git status --porcelain -- <file>`** — scoped to that file, so
   an unrelated dirty file does not read as a failed revert.

**Revert first on any error.** A missing runner, a hung run, an interrupted
session: before diagnosing anything, put the file back. The dirty-tree check in
Step 1 ran minutes ago and will not catch what is left behind now.

**A revert that fails aborts the run.** Say which file and what was done to it,
and file nothing. A gate that cannot put the code back has stopped being a gate.

**An axis candidate whose mutation went red is not proven and is not a
candidate** — something noticed, which is what load-bearing means. Drop it and
say so.

### A subsumption pair proves differently

One mutation cannot show subsumption: two examples can both catch "guard
removed" while only one catches "nil returned". So a pair takes **at least two
mutations of different kinds** to the production code the candidate reaches —
three where the code offers them — each run through steps 1–6 above. Where pairs
share that code, apply each mutation once and run every example of those pairs
in one invocation.

The pair is **subsumed** when the candidate caught at least one mutation and
every one it caught, the covering example caught too. One only the cover caught
is fine; one only the candidate caught refutes the pair, so stop mutating it
there. A candidate that caught nothing is dropped, and code offering only one
kind of mutation leaves the pair unproven. Keep the mutations both caught; they
are what Step 5 hands down.

## Step 5 · `file` — One ticket, or none

**A run that proved nothing files no ticket.** Say so in one line and stop.

Otherwise file exactly one issue carrying every proven example. Not one per
candidate: a prune is mechanical, so a ticket each buys an executor nothing and
costs a run each.

Each listed example carries the gate's run, written as something the executor
performs **before** deleting it — apply each mutation, run the named examples,
confirm each goes the colour the gate saw, revert, then delete. For an axis
candidate that is one mutation and the example staying green. For a subsumed
example it is the mutations both caught, with its covering example named, and
the cover going red on every one. That order is what makes it a check rather
than an observation; after the deletion there is nothing left to run.

**A covering example is never listed for deletion in the same ticket.** Where
another finding would list it, drop the subsumption that names it as cover; of
two examples covering each other, list one.

**Say why, beside the criteria, in the ticket itself.** By `kit:writing-tickets`
a per-example procedure is a route, and `/kit:triage` will try to rewrite it into
a fence. Next to the criteria, write a short paragraph saying the procedure is
the acceptance and must stay: a deletion guarantees behavior preservation
by construction, so the mutation check is the only thing an executor can fail.

The ticket carries **`technical-debt`**, and `kit:writing-tickets` owns the body.
Give it the empty blocking marker `<!-- kit-blocked-by: -->` so a sweep can see
it. Leave `ready-for-agent` off — that is a person's claim that a ticket is safe
to pick up unbidden, and this command filed it.

## Step 6 · `settle` — Triage the ticket it filed

**Only when Step 5 filed a ticket.** A run that proved nothing has nothing to
settle.

Run `/kit:triage <n>` on it now, in this session — a step, not an offer:
filed without the label, the ticket is invisible to `/kit:list` and to every
sweep. Triage runs unchanged and owns everything it writes; never relabel the
`technical-debt` kind, and never add `ready-for-agent` to cover a triage that
did not finish.

## Step 7 · `report` — Say what it found

The axis's contract governs the candidate lines. A subsumed example takes the
same one-line shape, with its cover and the mutations in the evidence clause:

```
spec/models/order_spec.rb:96    subsumed    by order_spec.rb:120; both caught guard removed, nil returned at order.rb:44
```

Then the four things only a suite sweep can report, one line each: candidates
the gate refuted, candidates left unproven, candidates beyond the band's cap,
and files or directories no agent assessed.

Close with the ticket number and what triage made of it — settled, closed, or
left open as not-now with its reason — or the one line saying nothing was
proven. A triage stopped partway means the run did not finish: say so, not that
it completed, and give `/kit:triage <n>` as what finishes it.
