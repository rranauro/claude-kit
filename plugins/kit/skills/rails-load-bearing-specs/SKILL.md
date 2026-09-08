---
name: rails-load-bearing-specs
description: The axis for judging whether one RSpec example is load-bearing — the positive definition, the three categories that convict a deletion candidate and the evidence each needs, and what is not a finding. Use when judging a spec file, proposing an example for deletion, or when another skill needs the load-bearing vocabulary.
---

# Rails Load-Bearing Specs

The axis for scoring **one example**. This is vocabulary and measurement, not a
procedure: it gives whatever step invoked it something to convict a deletion
candidate on, and something an adversarial pass can check rather than argue.

`kit:rails-codebase-design` scores the shape of a class. This scores whether the
suite would notice that class being wrong. Neither decides what to delete; the
invoking command owns that, and nothing here deletes anything.

**The unit of a finding is a single `it`.** A spec file is rarely wholly dead,
and "prune `foo_spec.rb`" is a diff nobody can review — the reader has to
re-derive the judgement for every example in it. Name the example, quote the
evidence, and let the file's other examples stand on their own.

## 1 — What a load-bearing example looks like

An example is **load-bearing** when breaking the code it covers breaks it.
Change the production line it exercises to something wrong, and this example is
what turns red.

That is the whole definition, and it is deliberately not coverage. Coverage says
the line ran. This says the suite *notices*. A line can run under a dozen
examples and still be free to return anything at all.

Three consequences worth stating, because each is a place the definition gets
read too narrowly:

**A wrong value is one way to be wrong; so is a missing effect.** An example
asserting that the record was enqueued, that the callback fired, that the
association was touched, is load-bearing over behavior no return value carries.

**Load-bearing is a property of the pair, not the example.** The same assertion
is load-bearing over the code that produces the value and dead weight over the
code that merely passed it along. Name which production code an example holds up
before judging it; an example with nothing named on the other side has not been
assessed yet.

**One example is enough.** A second example asserting the same failure adds
nothing to this axis and subtracts nothing either. Redundancy is a cost
question, not a load-bearing one, and section 3 sends it elsewhere.

## 2 — The three categories

Ordered by descending convictability. Each carries its own evidence rule,
because they are not equally provable and a pass that convicts them all on
reading is wrong about two of them.

### Tautology — evidence is local and quotable

The assertion restates the setup. Whatever the production code does, this
example passes.

The three shapes:

- **The assertion restates the setup.** A value is stubbed, computed nowhere,
  and asserted back.
- **A mock asserts the mock.** The double is told to receive `foo` and then
  asserted to have received `foo`, with no production object between them.
- **The matcher restates the line under test.** `validates :name,
  presence: true` and `it { is_expected.to validate_presence_of(:name) }` are
  one line written twice in two notations. Nothing about the application is
  asserted that the declaration did not already say.

**What convicts:** the setup line and the assertion line, quoted together from
inside the same example. This category needs nothing outside the file, which is
why it is first — the reader can check the finding without leaving it.

**What does not convict:** an example that reads as simple. Section 3 says so
again, because this is where the two get confused.

### Covers dead code — needs a runtime witness

The example holds up production code no live path reaches. If nothing calls it,
nothing notices it being wrong.

**Static call-site search cannot convict this in Rails.** `grep` finds direct
sends and nothing else, and the framework is built out of the other kind:

- callbacks registered by symbol — `before_save :normalize_phone`
- `send`, `public_send`, and `method(...)` with a computed name
- methods reached only from ERB, HAML, or a partial named by a variable
- `respond_to?`/`respond_to_missing?` dispatch
- serializer and presenter attribute lists, which name methods as data
- jobs and mailers enqueued by class name as a string
- STI subclasses instantiated from a `type` column
- controller actions reached only through `config/routes.rb`
- scopes and enums whose methods the framework generates

Convicting on a clean grep deletes the only example that would have caught a
live path, and the deletion is silent until the path runs in production.

**What convicts: a runtime witness.** An observation that the code did not
execute, admissible only when both hold:

- **It comes from production or CI**, not from a local run. A developer's
  machine exercises the paths that developer thought of.
- **Its window covers the path's known cadence.** A request path needs days; a
  monthly rake task needs a month. A window shorter than the cadence witnesses
  nothing, and reporting one as evidence is the failure this rule exists to
  prevent.

How a witness is produced is out of scope here — coverage in CI, a call-site
tracer, an APM trace, an instrumented deploy all serve. The rule above is what
the observation must satisfy to be admitted, whatever produced it.

Absent a witness, the example is unassessed, not convicted. Say that rather than
downgrading it to a weaker finding.

### Contradicts a stated requirement — the narrow one

The example asserts behavior that a live requirement artifact says is wrong: an
acceptance criterion, a `CONTEXT.md` definition, an ADR, a specification the
project actually keeps.

**This category convicts on contradiction, never on absence.** "No requirement
was found for this example" measures the search, not the example — and most
repositories hold no artifact stating their requirements, so the examples such a
search convicts are exactly the ones whose reason nobody remembers. Those are
the ones worth keeping.

**What convicts:** the artifact and the assertion, quoted side by side, saying
opposite things.

**And the finding is not "delete this."** Two live statements disagree; which
one is wrong is a person's call, and the code may be the half that changes. Say
what disagrees and stop there.

The cost, accepted deliberately: this category yields almost no deletion
candidates. That is the category working, not a gap to widen.

## 3 — What is not a finding

Raising any of these is the failure this axis exists to prevent. An example
resting only on one of them is not a weaker candidate; it is not a candidate.

- **A named unit's public surface is its own requirement.** A model, controller,
  view, concern, or service with an example per public method and per hydration
  path needs no further justification for them: the public method *is* the
  requirement. This refuses the second and third categories for those examples,
  and only those two — an example asserting the double it just set up is a
  tautology wherever it lives, and exempting whole layers would exempt exactly
  the files where tautologies collect.
- **A spec named for a bug or an issue number.** `it "does not double-charge
  (#4417)"` *is* the requirement artifact. It is the strongest evidence in the
  repository that someone once needed this, and the third category above reads
  it as such.
- **A characterization spec pinning behavior nobody remembers choosing.** By
  inspection it is indistinguishable from an example with no requirement behind
  it, and it is the most expensive kind to lose: it is the record of what the
  system does, held for the change that is about to alter it.
- **A boundary, nil, or empty case that reads as trivial.** Triviality is not
  tautology. `nil` handling asserts a real branch, and the assertion does not
  restate the setup — the setup is an absence.
- **A request or system spec that walks a whole path.** Its assertions are thin
  relative to the setup by construction; the path is what it holds up.
- **Slow, verbose, or duplicative.** Those are true of load-bearing examples too.
  A cost claim is a different axis with different evidence and a different
  disposition — a tag and a runner flag, not a deletion — and it belongs
  wherever the project decides what to run, never here.

The check that settles a candidate: **name the production code the example
holds up, and say what could go wrong there that only this example would catch.**
Name both and the example is load-bearing, whatever else is unlovely about it.
Name the code but nothing only this catches, and one of the three categories
above has to say which and produce its evidence. Fail to name the code at all,
and nobody has assessed it yet — which is not the same as it having no value,
and reporting it as a candidate is how a suite loses the examples it needed.
