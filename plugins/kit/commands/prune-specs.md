---
model: opus
---

Walk this project's spec suite, prove which examples can be removed or must be
rewritten, and file them as a ticket each way. It decides; it never deletes.

**Arguments:** none. The scan covers the whole suite, every time — expect tens of
minutes. Run it from the main checkout, against a clean tree.

**`kit:rails-load-bearing-specs` is the axis, and it owns the output contract
too.** What convicts, what does not, and what a pass says are all its. This
command finds the files, proves the candidates, and files the result.

**Three findings the axis does not own** — subsumption, the misplaced assertion
and the over-stubbed example: reading cannot settle any of them, and their only
evidence is a run of specs against the same mutation, which is this command's.

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

**Fill any room left in the band with misplaced assertions, then subsumption
pairs, then over-stubbed examples** — after the axis's categories, and only when
there is room, since a full band would discard the search. Removals come before rewrites,
then cheaper proofs first: an assertion costs one mutation and a pair several.

For misplaced assertions, fan out one agent per request spec file. Each returns
candidate assertions, one line each — the assertion's `file:line`, the
lower-layer code it reaches (the model, helper or service that computes what it
checks), and the spec files that own that code by the project's layout. **Never
propose an assertion about what the endpoint was sent, returned, or persisted as
given** — `site.reload.hero_headline` after a PATCH is the request spec's own
contract. The run cannot tell that apart from a misplaced one, since a mutation
to a model callback reddens both, so the reading has to. Nor propose an
assertion that is its example's only one: removing it would leave an example
asserting nothing, and the example stays.

For subsumption pairs, fan out one agent per spec directory, for
the directories holding at least two examples. A covering example may sit in
another file, so the unit is the directory: the files directly in it, not its
subdirectories. Each agent returns candidate pairs, one line each — the
candidate's `file:line`, the covering example's `file:line`, and the production
code both assertions reach.

For over-stubbed examples, fan out one agent per spec file. Each returns
candidates, one line each — the example's `file:line`, its subject, the stubbed
collaborator method, and the spec files that cover the subject by the project's
layout. **Only a stub of the project's own code is a candidate**: a gem, the
standard library or an external service has no implementation in this tree to
mutate. A mock asserting the mock is the axis's tautology, not this.

Reading only proposes; Step 4 proves. A file or directory whose agent fails is
unassessed for that finding, and Step 7 says so.

## Step 4 · `prove` — Mutate, observe, revert

**This is not the axis's runtime witness, and it does not stand in for one.** A
runtime witness is production or CI observation over a window covering the path's
cadence; this is a local mutation run. A dead-code candidate is convicted by the
axis on a witness or not at all, and passing this gate never supplies one — the
gate answers whether an example fires, never whether a path is live.

What it buys is the executor's signal. Deleting a spec produces a diff that
cannot fail: the suite is green by construction afterwards. So the decider has to
hand down something that can.

For each candidate in the band, one at a time — except that **candidates
reaching the same code share its mutation**: apply it once and run every example
they name in one invocation, whatever kind of finding each is.

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
three where the code offers them — each run through steps 1–6 above.

The pair is **subsumed** when the candidate caught at least one mutation and
every one it caught, the covering example caught too. One only the cover caught
is fine; one only the candidate caught refutes the pair, so stop mutating it
there. A candidate that caught nothing is dropped, and code offering only one
kind of mutation leaves the pair unproven. Keep the mutations both caught; they
are what Step 5 hands down.

### A misplaced assertion proves against its owning layer

One mutation, to the lower-layer code the assertion reaches, through steps 1–6
above — running the request example and the owning-layer spec files together in
one invocation.

The candidate is **proven** when the request example goes red *at that
assertion*; red elsewhere in the example, or not at all, drops it. Then record
which owning-layer examples went red too. None means the request spec is the only
thing noticing the break, and the assertion **moves**: a spec at the owning layer
is written, and the assertion leaves. Any means it is already noticed where it
belongs, and the assertion simply **goes**.

### An over-stubbed example proves against what its stub replaces

Mutate the stubbed method's real implementation in what the stub stands in for —
its returned value, or its effect. A mutation the subject never consumes goes
unnoticed for no fault of the spec, and convicts legitimate isolation. Run the
candidate together with every example covering the subject, through steps 1–6
above.

Mutations of different kinds, up to three as for a pair, stopping at the
**first one nothing went red under** — that mutation is the proof, and the
examples that stayed green are the evidence. Every mutation noticed by some
example covering the subject means the stubs hide nothing, and the candidate is
dropped. Candidates stubbing the same collaborator method share its mutations.

## Step 5 · `file` — Up to two tickets, or none

**A run that proved nothing files no ticket.** Say so in one line and stop.

Otherwise file one ticket per disposition: a **prune ticket** carrying every
finding proven for removal, and a **rewrite ticket** carrying every over-stubbed
example, each only when it has a finding. Not one per candidate: a ticket each
buys an executor nothing and costs a run each.

### The prune ticket

Each listed finding carries the gate's run, written as something the executor
performs **before** removing anything — apply each mutation, run the named
examples, confirm each goes the colour the gate saw, revert, then remove. That
order is what makes it a check rather than an observation; after the removal
there is nothing left to run.

- **An axis candidate:** one mutation, and the example staying green.
- **A subsumed example:** the mutations both caught, its covering example named,
  and the cover going red on every one.
- **A misplaced assertion**, listed by its assertion rather than its example:
  its mutation, and an owning-layer example going red under it — the one named,
  or for a move the one the executor writes first. Then the assertion goes, and
  the request example still passes without it.

**An example named as evidence is never listed for deletion in the same
ticket** — a cover, or the owning-layer example a misplaced assertion goes in
favour of. Where another finding would list it, drop the finding that names it;
of two examples covering each other, list one. A candidate proven against
several covers is listed once, under one cover that is itself not listed.

**Say why, beside the criteria, in the ticket itself.** By `kit:writing-tickets`
a per-example procedure is a route, and `/kit:triage` will try to rewrite it into
a fence. Next to the criteria, write a short paragraph saying the procedure is
the acceptance and must stay: a deletion guarantees behavior preservation
by construction, so the mutation check is the only thing an executor can fail.

Give it the empty blocking marker `<!-- kit-blocked-by: -->` so a sweep can see
it.

### The rewrite ticket

One criterion per over-stubbed example: **afterwards, an example covering the
subject goes red under the named mutation** — the stubbed collaborator, and what
was done to its implementation. Rewriting the example against the project's own
test data meets it, and so does removing it where another example covering the
subject now notices. Which test data is the project's, never this command's choice.

**An example the prune ticket lists for deletion is not listed for rewrite.**
Its blocking marker names the prune ticket where one was filed, and is empty
otherwise: a rewrite may remove an example the prune's checks still run as a
cover.

### Both tickets

Each carries **`technical-debt`**, and `kit:writing-tickets` owns the body.
Leave `ready-for-agent` off — that is a
person's claim that a ticket is safe to pick up unbidden, and this command filed
it.

## Step 6 · `settle` — Triage the tickets it filed

**Only when Step 5 filed a ticket.** A run that proved nothing has nothing to
settle.

Run `/kit:triage <n>` on each now, in this session, the prune ticket first — a
step, not an offer:
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

A misplaced assertion likewise:

```
spec/requests/sites_spec.rb:58  misplaced   slug derivation dropped at site.rb:22; no owning-layer spec noticed — move
spec/requests/sites_spec.rb:71  misplaced   total rounding removed at order.rb:40; order_spec.rb:88 noticed too — goes
```

An over-stubbed example names its stubbed collaborator, the mutation, and the
examples covering the subject that stayed green:

```
spec/services/checkout_spec.rb:42  over-stubbed  stubs Pricing#total; total inverted at pricing.rb:18, unnoticed by checkout_spec.rb:42, :57 — rewrite
```

Then the four things only a suite sweep can report, one line each: candidates
the gate refuted, candidates left unproven, candidates beyond the band's cap,
and files or directories no agent assessed.

Close with each ticket's number and what triage made of it — settled, closed, or
left open as not-now with its reason — or the one line saying nothing was
proven. A triage stopped partway means the run did not finish: say so, not that
it completed, and give `/kit:triage <n>` as what finishes it.
