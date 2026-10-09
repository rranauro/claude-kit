---
name: rails-excludable-specs
description: The axis for judging whether one RSpec example may be left out of a project's default suite run — what makes an example excludable, the evidence rarity and cost each need, what is not a reason, how an excludable example differs from a deletable one, and the tag that opts it back in. Use when deciding what a default run should skip, when judging whether one slow or rarely-relevant example earns its place in every run, or when another skill needs the excludable vocabulary.
---

# Rails Excludable Specs

The axis for scoring **one example** against the default run. This is vocabulary
and measurement, not a procedure: it gives whatever step invoked it something to
justify an exclusion on, and something an adversarial pass can check rather than
argue.

`kit:rails-load-bearing-specs` asks whether an example is worth keeping. This
asks whether a kept example is worth running every time. Neither tags or deletes
anything; the invoking command owns that.

**The unit of a finding is a single `it`**, for the sibling axis's reason: "skip
`foo_spec.rb`" makes the reader re-derive the judgement for every example in it.

## 1 — What an excludable example looks like

An example is **excludable** when all three hold:

1. **It is load-bearing**, by `kit:rails-load-bearing-specs`. One that is not is
   a deletion question, and tagging it keeps paying for an example that adds
   nothing.
2. **The path it holds up runs rarely**, relative to how often the default suite
   runs.
3. **Running it costs something real** — time measured on an actual run, or a
   resource the example reaches beyond the process.

Rarity and cost together are the whole subject. Either alone is not enough: a
costly example over a hot path is the suite doing its job, and a cheap example
over a rare path costs nothing to keep running.

**Check rarity first, then cost, then load-bearing.** Rarity is a lookup and
fails most examples; the load-bearing judgement is the expensive one, so spend
it only on what survives the other two.

### Excludable is not deletable

| | Deletable | Excludable |
|---|---|---|
| What it claims | The example adds no value | The example adds value, but not on every run |
| Is it load-bearing? | No — that is the finding | Yes — that is a precondition |
| Evidence | A category in `kit:rails-load-bearing-specs` §2 | The path's cadence, and the run's cost |
| What happens | The example is removed | The example is tagged, and runs when asked for |
| Undone by | Rewriting it from memory | Removing a tag |

The last row is why exclusion is the safer finding — and why it takes a lower
bar of evidence than a deletion, not no bar.

## 2 — The categories

Each names a kind of path that is rare by construction. The categories describe
**where rarity comes from**.

### Reference-data artifacts

The example confirms a file or table the application ships as data — a
country list, a tariff schedule, a seeded taxonomy — that changes when someone
deliberately refreshes it.

**Rarity evidence:** the artifact's refresh path — the task, script, or manual
step that rewrites it — and its history. A file last changed twice in a year
changes on that cadence.

### Output of an artifact-generating command

The example runs a command that writes a generated artifact — a schema dump, an
OpenAPI document, a fixture export, a compiled report — and asserts what came
out.

**Rarity evidence:** the entry point that runs the generator, and who runs it. A
generator invoked by a release step or by hand runs on that cadence, not on every
change.

### Rarely-run rake tasks

The example drives a task reached only by a person or a schedule — a backfill, a
yearly rollover, an operator's repair task.

**Rarity evidence:** the task's entry points — the schedule entry or runbook that
invokes it, or the absence of any. Name the cadence the schedule states; a task
with no schedule runs when someone runs it, and the example runs then too.

### Cost — needed by every category

- **An external reach**, read from the example itself — the network, a large
  fixture on disk, a service it boots — that makes the run expensive or fragile
  on a machine without it. Name the resource. Look for this first; it costs no
  run.
- **Or measured time**, never estimated from reading. Take every candidate's
  number from one run — the project's CI timings, or one `--profile <n>` over the
  candidate files with `n` large enough to list them all. Report the number.

## 3 — The one check before any exclusion

The load-bearing check already named the production code the example holds up.
**Ask one more thing of it: what else in the default run notices it being
wrong?**

Excluding an example removes its notice from every default run. That is the
intended saving for the rare path. It is a silent loss for any other code the
same example happens to hold up. A rake task's example that is the only thing
asserting a shared model method has stopped guarding that method, on every path,
until someone asks for the tag.

- **The code it holds up is reached only through the rare path**, or something
  in the default run also notices it being wrong → the exclusion costs only what
  it intends.
- **It holds up code a frequent path also reaches, and nothing else in the
  default run notices** → not excludable. The cost claim is real; the rarity
  claim is false for that code.

## 4 — What is not a reason

An example resting only on one of these is not a weaker candidate; it is not a
candidate.

- **Slow.** Cost without rarity (§1). Slow alone is a case for making the
  example faster, not for running it less.
- **Verbose or duplicative.** The same refusal the sibling axis makes: true of
  load-bearing examples too, and no evidence that the path is rare.
- **Flaky.** Excluding a flaky example hides the flake and keeps the cost of
  whatever it is flaking on. It is a defect to fix, on its own ticket.
- **"Nobody changes this code."** That is a claim about how often the code
  changes, not how often the path runs. Code that rarely changes and runs on every
  request is exactly the code whose break nobody expects.
- **It has a tag already.** `:slow`, `:js`, or a project's own tag records
  someone's earlier judgement, not evidence. Assess the example as if it were
  untagged.

## 5 — The convention

An excludable example carries one RSpec metadata tag:

```ruby
it "rebuilds the country list from the upstream file", on_demand: true do
```

`on_demand` names what happens to the example, not why it is expensive, so the
same tag serves every category. Tag the `it`, or the `describe` that holds only
excludable examples. Tagging a group that also holds load-bearing,
default-run examples excludes them too.

The consuming project leaves the tag out of its default run — conventionally
`config.filter_run_excluding on_demand: true` in its RSpec setup. That
configuration is the project's own; this axis states the convention and supplies
none of it.

**Running an excluded example when someone asks for it:**

- `bundle exec rspec --tag on_demand` runs every excluded example. A tag named on
  the command line overrides a configured exclusion of the same tag.
- `bundle exec rspec spec/path/to/file_spec.rb:42` runs one. A location overrides
  exclusions for examples in that file.

Whoever changes the code an excluded example holds up runs it then.

## 6 — What a pass reports

The frame is `kit:rails-load-bearing-specs` §4's — one line per finding,
unassessed lines, the one-sentence empty result, nothing else. Here a line
carries the example's `file:line`, the category, and the rarity and cost
evidence in a clause; an unassessed line says what was missing; the empty result
is "nothing excludable".

```
spec/tasks/rollover_spec.rb:18      rake task        yearly schedule; 41s measured
spec/lib/countries_spec.rb:7        reference data   refreshed by hand, 2×/yr; reads 3MB file
spec/models/export_spec.rb:55       unassessed       generator cadence found; no timing for the example
```
