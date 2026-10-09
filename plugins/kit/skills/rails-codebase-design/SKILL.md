---
name: rails-codebase-design
description: The axis for judging object shape in a Rails codebase — what a well-formed class looks like, what to count when one isn't, the structural moves that fix it, and what is not a finding. Use when comparing design approaches, judging a proposed class or extraction, or when another skill needs the object-shape vocabulary.
---

# Rails Codebase Design

The axis for scoring **object shape**. This is vocabulary and measurement, not a
procedure: it gives whatever step invoked it something to rank approaches on,
and something an adversarial pass can check rather than argue.

`kit:behavior-placement` answers *whose* the behavior is. This answers *what
shape* the result should take. Neither decides what to build; the invoking
command owns that. Its vocabulary is §5.

## 1 — What a well-shaped object looks like

Seven properties. Each is checkable by reading the file, and an approach either
has it or does not.

**`initialize` says what it takes — or the framework already said it.** Named
arguments. Required and optional are distinguishable at a glance, and every
optional one carries a sensible default. A caller should be able to construct
the object correctly without reading the body.

Where the object is an ActiveRecord, `find` and the associations *are* the
construction: the state is established before any of your code runs. A concern
adding instance methods over that state is the same well-shaped object, and is
the preferred way to organise model behavior — not a fallback for when there is
nothing to construct.

**It takes the narrowest input it actually uses.** If the object calls one or
two methods on a record, it takes those values — and the reader that produces
them goes on the record, where the data lives. Taking the record instead leaves
the dependency surface unpinned: what the class depends on is "whatever that
model has," it widens silently on the next change, and someone planning a change
has to load the model into their head to reason about the class at all.

Narrowing costs something, which is why it gets skipped: work moves *out* of the
class and onto a caller, and giving work away reads as scope creep. It isn't. A
class that shrank because a model gained a named reader is the transaction
working correctly — the extraction became legible, and it landed where the data
already was.

This is about objects you construct. Where the framework constructed it, the
previous property already applies: `find` and the associations are the input,
and there is nothing to narrow.

**Accessors expose the inputs and the working state.** What the object was
given, and what it computed along the way, are readable. A caller can see what
it is working from; a test can assert on it without reaching into instance
variables.

**Methods chain, and chain by returning `self`.**
`SomeClass.new(data: some_data).method1.method2` composes because each step
returns something the next step can act on. A method that computes a value and
returns it bare loses the name at the call site:

```ruby
a = model_instance.method1   # what is a?
```

Assign the result to an accessor-backed attribute and return `self`, and the
call site says what it got:

```ruby
a = model_instance.method1.y   # a is y
```

The chain can then continue into the next method or terminate in an output
format. This is why the accessor property above matters: the accessors are what
make chaining legible rather than just terse.

**Output formats terminate the chain.** When the object serves several
representations, `.to_json`, `.to_yaml`, and `.to_csv` hang off that same
chain — one method per format, not a separate class per format and not a format
argument threaded through the construction.

**Method names are declarative.** A name says what comes back, not what the
method does inside. `headers`, not `parse_headers`. `preview`, not
`build_preview_string`.

**The namespace is the data structure.** `Csv`, `Html`, `Api` — the outer name
tells a reader what kind of data is in play. Children may name the role within
it: `Api::Request`, `Api::Response`, `Csv::Document`, `Csv::Editor`. The
constraint is that the namespace carries the data; a role name underneath it is
correct, not a violation.

*Which* data is decided at the call sites, not by reading the class. An object
that takes one kind of data and returns another — parses HTML, emits prompt
text — is claimed by both namespaces, and the constructor argument is the
weaker claim of the two. Where many producers feed one consumer domain, the
class belongs to the consumer and is named for it; where one producer feeds many
consumers, it belongs to the data. `kit:behavior-placement` Check 3 lists the producers and
consumers that decide which.

An object with all seven is legible from its call site. Someone planning a
change can tell what it holds and what it answers without opening it — which is
the whole point of the axis.

## 1.5 — The properties applied once, end to end

The properties describe a destination. This shows the move, because the move is
the part that does not follow from knowing the destination — and a redesign that
starts from the bad class and stays inside it reliably fails to find it.

A class assembled three sourcing paths over one derivation. Two callers: an
offline harness working from a theme file, and a live page in the app.

**Before** — the class holds every path, and both callers hand it a record:

```ruby
X.for_page(page)            # -> { manifest:, style_block:, example_section: }
X.for_template(template)    # -> same hash
X.from_html(html)           # -> same hash
```

**After** — three panels, and the middle one is the lesson:

```ruby
# caller
Ai::Request::Page.new(page.component_source_html, page.template).manifest

# model — the extraction moved here
class Page
  def component_source_html   # narrowest input: the class needed a String
    components.kept.map(&:current_html).join("\n")
  end
end

# class
class Ai::Request::Page
  def initialize(html, template)   # arity 2, one aggregate — nothing unnamed
  def manifest        -> String    # declarative name, typed return
  def style_block     -> String
  def example_section -> String
end
```

Read the annotations, not the shapes. Each one names the property or count it
answers; nothing here is a template, and copying the surface — naming things
`Document`, returning `self` — while the input stays a record reproduces the
original defect with better vocabulary.

Three things this shows that a single-class example cannot:

- **The class got smaller because a caller got a reader.** `component_source_html`
  is the whole narrowing property in one method, and it lives on the model, not
  in the class being designed. Any before/after that shows only the class makes
  this invisible — which is why the obvious redesign preserves the record
  argument and lands back where it started.
- **Two of the three entry points were deleted, not converted.** They were not
  requirements; they were sourcing decisions the class had absorbed from its
  callers. The callers took them back, and each one now reads what it sources.
- **The hash became the object.** Its three keys were always the three methods.

The one-line anti-example, which is all one is worth: `def self.for_page(page)`
— the first parameter is the receiver, and the state was never named. A longer
bad example teaches the wrong lesson, because real misplaced classes have good
names, real comments, and clean tests. They do not look bad. Matching against a
catalogue of ugly shapes is how they get missed.

### The same move at one-method scale

The example above is a whole-class redesign. The more common case is one return
type, and it is worth showing because nothing is extracted and nothing is deleted.

**Before** — the object is built, asked for its table, and thrown away:

```ruby
rates = RateTable.new(carrier: carrier, zones: zones).rates   # -> Hash
rate  = rates[[line.zone_id, line.weight_class]]
```

**After** — the object is kept, and asked:

```ruby
rate = rate_table.rate(line.zone_id, line.weight_class)

class RateTable
  def rate(zone_id, weight_class) = rates[[zone_id, weight_class]]
  def rates = @rates ||= …          # the index, memoized, one query
end
```

Three consequences, none of them visible from the return type alone:

- **The composite key stopped being public.** It was never data a caller needed;
  it was the lookup's internal index.
- **Two threaded parameters left the caller.** A hash has to be passed down to
  wherever its key can be built. An object does not.
- **Memoization became possible.** A discarded object cannot cache, so the
  caller's workaround is to hoist the construction and thread the result — which
  is the threaded-argument count arriving by a different road. Read that
  direction: the threaded argument was the symptom, the discarded object the
  cause. Treating the symptom produces a caller that hoists a hash and still
  builds keys.

## 2 — What to count when it isn't

Counts, not preferences. Each states what the number means and stops there.

**Construction arity.** More than three arguments, or arguments drawn from more
than two aggregates: a structure nobody has named is being assembled at every
call site. The missing structure is the finding, not the length of the list.
_Avoid_: long parameter list, too many params.

**The threaded argument.** Several methods passing the same argument to each
other — class methods, or private instance methods handing it down a chain. That
argument is the `initialize` of an object that does not exist yet, and the methods
threading it are its instance methods. Where they are already instance methods of
some object, the argument is state that object never named: it gets built at the
top of the chain and carried by hand, one parameter at every hop, because there is
nowhere for it to live.
_Avoid_: tramp data, data clump, prop drilling.

**The first-parameter receiver.** A class method whose first parameter is the
record it operates on is an instance method that never moved onto the instance.
_Avoid_: static helper, utility method.

**The borrowed receiver.** An instance method whose body reads no state of its
host: its arguments and the globals are its whole input. Mirror of the count
above — that one is behavior that never moved *onto* the instance, this one is
behavior that never moved *off* it. Both are one rule read from both ends, and
this end is the one that accumulates silently, because putting it here was
locally the shortest thing to write and nothing resisted.
_Avoid_: feature envy, helper method.

Reaching an association merely to construct a collaborator is not reading own
state. Whoever holds the record already holds the association, so a method that
opens `Collaborator.new(x, record.site)` is the caller's convenience with a
receiver attached — the state it works from is the collaborator's.

An association that *is* the constraint is the exception. Where an identifier
arrives from outside — a browser parameter, an API payload — and the method
resolves it through an association, that association is what stops one tenant
handing another's record to this one. It reads no state of its host and is
still correctly placed, because the scoping is the host's own job. The
discriminator is what the association is asked for: a collaborator to work
*from* counts, a constraint on an untrusted id is the record doing what only
it can. Evicting the second is the count deleting a cross-tenant guard.

Count it by enumerating every method against what it reads of `self`: nothing,
one value it could have been handed, or state only this record holds. The first
two are the count; the third is the class. This is what names why a class
reached a length limit with sixty short methods — the length is the symptom, the
borrowed receivers are the cause, and a split that relocates them into a new
module carries them instead of landing them.

Landing one is a move before it is an extraction. The method already answers
about some record, and that record is usually the receiver already waiting for
it — a new class is what the absence of one buys, not the default response to
the count.

**The hidden instance.** A class method that constructs an instance and calls
one method on it — `Thing.call(x)` wrapping `new(x).call` — so no call site ever
holds the object. It fires where that instance exposes something its callers
can no longer reach — a public reader, a further method, or a value it computed
that a caller goes on to work out again. Name the call sites that lose it; the
fix is to let them hold the instance.

A scope, a finder, or a factory that hands the instance back has no hidden
instance, and neither does an instance exposing only its one answer (§3). Where
its first parameter is the record operated on, report the first-parameter
receiver instead: moving the method onto that record deletes this one with it, while
exposing the instance would keep the misplacement.
_Avoid_: callable, service object.

**Reaching back to the class.** Repeated `self.class.` inside instance methods
means behavior parked at class level that the instance needs. A handful is
noise; dozens is one class living as two.
_Avoid_: class-level coupling.

**The doubled name.** The same name defined twice — class and instance, or
twice at one level — and especially with differing signatures: two things are
wearing one name.
_Avoid_: overload, shadowing.

**The unearned construction.** An alternate constructor resorting to
`allocate`, `send(:initialize_…)`, or a mode flag, because the real
`initialize` already claimed the signature: either two objects are in here, or
the state was described wrong.
_Avoid_: factory hack, alternate initializer.

**The unpredicted return type.** Two public methods, and the class name predicts
one of their return types. The method answering the other is a separate object
wearing this one's name, and naming which one is the count.
_Avoid_: mixed responsibilities, SRP violation.
Constructed: `Csv::Exporter` predicts the exported rows, so `#rows` answering
them in memory is the method its name covers, and `#write` answering the file
paths it created is the separate object. Both still answer something about one
export, which is the version of this worth stating. That the two types diverge
is the tell that sends you looking, not the test: `.run` answering a report
beside `.call` answering a persisted record fires on sight, but two renderings of
one answer have plenty in common, and a count led by their divergence is a count
a reader discharges. The differing names are the disguise — the doubled name
above needs one name twice, and `kit:behavior-placement` Check 2's search passes
both rows `only here`, since neither method computes the other's answer. **It
fires from the class**: two return types and a name are the whole of it. Reach
for Check 3's list of producers and consumers when the name predicts both types
or neither, and again once it fires — that list names the callers that move when
the object splits.

**The same-signature constructors.** Two constructors of the same arity
returning the same type — `Thing.from_json(str)` and `Thing.from_text(str)`,
both arity 1, both `-> Thing`. Both are clean, which is why the unearned
construction above stays quiet, and a caller picking between them by name is
picking a mode. A mode is an argument. Check 2's search does reach this pair —
both constructors get rows, each naming the other as `duplicated` — and what it
cannot supply is where that mode goes once the two collapse to one
implementation.
The shortest path from there is a third class method. It goes in an argument, or
at the call site: either the decision was the caller's, or the caller could not
have known which constructor to call.
_Avoid_: named constructors, mode constructors.

Those two counts are one rule read from both ends: the interface is a type
signature. Same types in and out means two objects where there should be one;
a return type the name does not predict means one object where there should be
two.

**The duplicated answer.** A method that recomputes something the application
already establishes elsewhere duplicates the definition, and the two copies
diverge on the first change. Recomputing from a serialized form — HTML, JSON,
CSV headers — what the application already hydrated is the usual case.
_Avoid_: fork, forked — that word means code copied from an upstream.

A column does this too, and reads as schema rather than as a copy, which is why
it survives the count as written. A column caching a fact the rows already
answer — `first_activated_at` beside a child carrying an `active` flag,
`item_count` beside the items — is one definition stored twice. The tell is at
the writers, not in the schema: every path that could change the underlying fact
has to remember to stamp it, so a writer added later arrives carrying a comment
explaining that it marks the column too. That comment is this count, written
down instead of acted on.

**The fixed-key hash.** A method returning a hash whose keys are known when the
method is written is a class that was never named — its keys are the methods it
would have had. The cost lands at every call site: readers key into it by
symbol, `.to_s` defensively because nothing guarantees a type, and no name for
the thing survives the assignment. Section 1's chaining property does not catch
this, because a hash is a legal terminator; the tell is that the keys are
literal, not that a hash came back. When the keys are computed rather than
literal, the next count applies.
_Avoid_: primitive obsession, data bag.

**The keyed lookup handed out raw.** A method returning a hash the caller
dereferences by a key it builds itself — `rates[[zone_id, weight_class]]`.
Sibling of the fixed-key hash, and the reason that count's "keys are literal"
tell walks past it: the keys are computed, so nothing looks hardcoded. The cost
is worse, not better — the caller now knows the key's shape and order as well as
the value's, every call site restates that contract, and a wrong key yields `nil`
rather than an error. The fix is not a new class; the object already exists and
was discarded. Keep the hash private and add the question:
`rate(zone_id, weight_class)`.
_Avoid_: leaky hash, exposed index.

**The unheld namespace.** A class whose returns make sense to only one caller,
filed under the namespace of the data it reads rather than the one it serves.
The tell is the return type: ask what a caller from the namespace it currently
sits in would do with the value. If nothing there would ever want it, the class
is filed under its input instead of its owner.
_Avoid_: wrong module.

**The loop that produces and consumes.** A loop whose body creates something and
then feeds it to a second operation — a record created, then its children built
from it. Tell: a local assigned inside the block and then passed to something that
writes further records. Building a record, mutating it, and saving it is one
operation on one object — that is not this count, and a loop doing only that is
correct. Two passes over the collection, or two methods, say the same thing with a
failure boundary a reader can state: all of the first, then all of the second.
Where it shows up first is the spec — the second operation cannot be exercised
without driving the first.
_Avoid_: mixed loop.

This is the only count about the inside of a method body. It is here because the
shape survives every other check: arity, naming, and placement can all be correct
while the body still interleaves two operations that had no reason to be
interleaved.

**The accreted interface.** An object whose interface carries three or more
members that each serve at most one call site outside the object and its specs.
A member is a public method, a class method — constructors included — an
optional `initialize` keyword, or a parent's hook that one subclass overrides
for one caller. Each arrived with the capability that needed it and cleared §3 on
its own, which is why the count exists: the interface became a list of callers
rather than an API, and no single change owns that. Its cost is the object's
history — each capability landed as a bespoke member, and the next one will too —
which is the change it makes harder that §3's closing check asks for.

The members it counts are the ones that differ from each other. A reader per
channel — one signature and one return type, repeated once per channel — is a
single question asked of the object many times. That is the API working, however
few callers each one has. The count is for members that are each shaped to a
different caller: `authored_by?(mode) -> Boolean` for one view,
`removed_fields -> Array` for one job, `self.for_import(file)` for one importer, a
`preview:` keyword only the test harness passes.
_Avoid_: undertow, sprawl, bloat, god class, public surface.

**The deletion test.** Imagine the object gone. If the complexity vanishes, it
was a pass-through. If it reappears at every caller, it earns its place.
Applies to anything being proposed as much as to anything already written.
_Avoid_: shallow module.

## 2.5 — The moves a finding can call for

A count names what is wrong with one object. Some findings are fixed inside that
object; the ones here are fixed by reshaping a set of classes, and the axis
names four. Each points back to the counts that suggest it and adds no count: an
observation no count covers is stated with the move, not in §2.

**Where the invoking step asks for alternatives and more than one move fits a
finding, show each one's After and mark none preferred.** Choosing between them
is the rank, and the rank belongs to that step. A step whose report carries one
After per finding keeps it — the moves widen what it may propose, not how many
it writes.

**Shared parent.** Several objects differ along one axis and repeat the rest, so
each value of that axis is a class under a parent that holds what they share.
_Tell_: the unearned construction's mode flag; and — no count covers it — a
`case` on one argument, or that argument read in method after method to pick a
step.
_Cost at the call site_: the caller names a class instead of passing a mode.
Where the mode is computed at runtime, one lookup from value to class returns at
that site. The reach is every call site that passes the mode.

**One object over a library reached raw.** A library, or a derivation, is called
directly at many call sites and each re-derives from the result inline; one
object named for the data takes the calls and answers the questions they were
re-deriving.
_Tell_: the duplicated answer, recurring at each site that recomputes from the
serialized form; and — no count covers it — the number of call sites reaching
the library raw, or once the object exists, raw references to the library
outside it.
_Cost at the call site_: every raw call site moves onto the object. The reach is
that count of raw references.

What separates those two is where the variation lives. Variation in what is
constructed with — the same operations on different data — is one object: the
varying thing becomes its input, whether that object gathers calls from many
sites or already exists with a mode it should have taken as data. Variation in
the steps, keyed on one argument, is a shared parent. It is countable on the day
the class is written, as references to that argument inside the class, and the
count rising with each feature is the shared parent arriving late. Variation in
both is the case where both fit.

**Separate namespaces.** Classes filed together under one namespace serve
different callers, so a reader cannot tell which belong to which, and the set
splits along its consumers. Find them with one search for references into the
namespace, grouped by the calling namespace; `kit:behavior-placement` Check 3
places any class that grouping leaves ambiguous. Check 3 places one class, and
this move is the set moving together.
_Tell_: the unheld namespace, fired by several classes in one namespace with
different consumers.
_Cost at the call site_: every constant path outside the moved set changes. The
reach is each reference to a moved constant.

**A mixin for a family with no shared parent.** Several classes share behavior
but cannot share a parent — they already have different ones, or a parent would
hold this behavior and nothing else they share — so it goes in one module each
of them includes. Where the family is models, that module is a concern and is
called one; §5's *Avoid* line on **Concern** is why.
_Tell_: the duplicated answer, or the doubled name, across classes that sit
beside a parent rather than under it.
_Cost at the call site_: none. The cost lands on the definitions, and there is
no common ancestor a caller or a test can check against.

### One finding, two moves

The examples in §1.5 end in one After. This one is a finding that two of the
moves above fit.

**Before** — one class, and a mode chooses what it does:

```ruby
Ai::Request.new(site, mode: :edit, component: component).prompt
Ai::Request.new(site, mode: :add_section, position: 3).prompt
```

**After, one object** — the mode became what it is constructed with:

```ruby
Ai::Request.new(site, target: component).prompt
Ai::Request.new(site, target: page.slot(3)).prompt   # target answers #context
```

It answers the rule above for variation in the data.

**After, shared parent** — each value of the mode became a class:

```ruby
Ai::Request::Edit.new(site, component).prompt
Ai::Request::AddSection.new(site, 3).prompt

class Ai::Request::Base
  def initialize(site)
  def prompt -> String       # shared steps; subclasses supply theirs
end
```

It answers the same rule for variation in the steps.

The Before shows only its call sites, so both fit. Its body is what would favour
one.

## 3 — What is not a finding

Raising any of these is the failure this axis exists to prevent. Scoring an
approach down for one of them is wrong.

- **Not injecting dependencies is fine.** Do not ask for them to be passed in.
- **A method that changes its own record is correct.** Owning state and
  changing it is the object doing its job.
- **The database is not a dependency to inject.** An object reaching its own
  associations and scopes is normal, and injecting them costs construction
  arity, which section 2 then charges for.
- **"It needs testing without the database" is not a reason to move behavior.**
  Narrow what the behavior depends on instead; the testability follows and the
  code stays where it belongs.
- **A command object with nothing to hold is not a hidden instance.** Where the
  instance answers only what its one call returns, `Thing.call(x)` and
  `Thing.new(x).call` read the same at every call site, so no caller loses
  anything. The convenience method is the most common in Rails; filing it
  everywhere files a count no caller pays for.
- **Framework conventions are not smells.** Callbacks, scopes, concerns,
  validations, and generated methods are the language being written in. What
  they hold is scorable; that they exist is not.
- **More files is not depth, and neither is fewer.** What a caller has to learn
  is the measure.
- **A length limit is not a finding, and not the definition of done.** A long
  class usually is holding something, and section 2 has the counts that name
  what — so the number is where you start looking, never what you report on its
  own and never the criterion a proposal is measured against. A refactor that
  satisfies every count and lands over the limit has succeeded; one that lands
  under it while satisfying none has not.
- **A method with one caller is not a finding on its own.** It costs nobody:
  the deletion test sends its complexity back to that one caller. What §2's
  accreted interface charges is the object, never the single method.
- **A mode whose values differ only in data is not a shared-parent finding.**
  §2.5's rule sends it to one object.
- **A library reached raw at one or two call sites is not a one-object
  finding**, and neither is one reached for data the object is not named for.
  The object is named for its data, not its library, so XML parsed through the
  library an HTML object wraps belongs outside that object.
- **A namespace whose returns make sense to every caller in it is not a
  separate-namespaces finding**, however many classes it holds.
- **A module one class includes is not the mixin move.** It is that class's
  code in another file.

The check that settles it: **name the caller it costs, or the change it makes
harder.** Friction that can name neither is not a finding.

## 4 — Front-end modules in the same codebase

Same six, restated for the JavaScript alongside.

A Stimulus controller's declared values and targets *are* its `initialize` —
that declaration is what a caller must supply, and it is what gets counted. A
long list of values and targets is the arity count in another notation: a
structure nobody has named, assembled in the markup at every use site.

Accessors, declarative naming, and chaining carry over unchanged. So does the
doubled name: a concept computed both server-side and in the module means one
of them is the definition and the other is recomputing it.

One exclusion is specific here. **A controller that renders what the server
calculated is complete, not thin.** Where the convention is that the server
computes state and hands the result to the front end, scoring such a module as
thin — or proposing to move the calculation into it — misreads the
architecture.

## 5 — Vocabulary

The concepts and structural nouns the axis is written in, defined once. Each
count in §2 is its own entry where §2 states it, with its *Avoid* line there.
`kit:behavior-placement`, the architecture scan and the reviews that cite this
axis use these words as written.

**These terms govern code shape only.** A host project's own glossary governs
its domain. Where it uses one of these words for a domain concept or an in-app
act — a Component, a layer, a derivation, an act it calls hydrating — the host's
meaning stands for that sense, and this one for code mechanism. A design pass
writing in a host project says which sense it means rather than reusing the word
bare. No *Avoid* line here forbids a host's domain noun.

### Concepts

**Object shape**:
What a class takes, holds and answers, read from its interface and its call
sites. The thing §1 describes and §2 counts.
_Avoid_: design quality, code quality.

**Interface**:
An object's `initialize` and the signatures of its public methods — what a
caller must supply and what each method returns.
_Avoid_: seam, public surface.

**Call site**:
A line that constructs an object or calls one of its methods. Where shape is
paid for.
_Avoid_: invocation point.

**Derivation**:
An answer computed from data the app already holds.
_Avoid_: shared derivation.

**Hydrate**:
To fill an object's state from what the app already holds, so its fields are
named and typed. The hydrated form is what a derivation reads.
_Avoid_: inflate, materialize.

**Producer / consumer**:
Who constructs an object, and who calls it. `kit:behavior-placement` Check 3
lists both, and the two lists decide the namespace.
_Avoid_: boundary type, census.

**Move**:
A change that resolves a finding — inside one object, as §1.5 shows, or across a
set of classes, as the moves §2.5 names.
_Avoid_: refactoring, pattern.

**Rank**:
Ordering the moves that fit one finding, with one recommended. The invoking
step's act, never this axis's.
_Avoid_: preference, best fit.

### Structural nouns

**Model**:
An ActiveRecord class that owns its data and the behavior over it.
_Avoid_: record class.

**Concern**:
A module of instance methods over a model's established state. The preferred way
to organise model behavior, and the existing owner to extend before opening a new
class.
_Avoid_: seam, mixin, trait.

**Domain object**:
An object constructed from data the app has hydrated, named for a domain concept,
answering derivations over it. The second home for model behavior, after a
concern.
_Avoid_: PORO; value object, unless it really is immutable and compared by
value.

**Service**:
A class for an operation no model owns. `kit:behavior-placement` Check 1 says
when one is warranted.
_Avoid_: interactor, operation class.

**Namespace**:
The outer constant that names the kind of data in play — `Csv`, `Html`, `Api`.
Children under it may name a role.
_Avoid_: module (for a class), package, boundary.

**Aggregate**:
A model and the records it owns, treated as one unit for reads and writes.
_Avoid_: object graph.

**Accessor**:
A reader exposing an object's input or its working state, so a caller or a test
can see what it is working from.
_Avoid_: getter, attr.
