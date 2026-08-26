---
name: rails-codebase-design
description: The axis for judging object shape in a Rails codebase — what a well-formed class looks like, what to count when one isn't, and what is not a finding. Use when comparing design approaches, judging a proposed class or extraction, or when another skill needs the object-shape vocabulary.
---

# Rails Codebase Design

The axis for scoring **object shape**. This is vocabulary and measurement, not a
procedure: it gives whatever step invoked it something to rank approaches on,
and something an adversarial pass can check rather than argue.

`kit:behavior-placement` answers *whose* the behavior is. This answers *what
shape* the result should take. Neither decides what to build; the invoking
command owns that.

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
weaker claim of the two. Many producers feeding one consumer is a boundary
type, and belongs to the consumer; one producer feeding many consumers is a
shared derivation, and belongs to the data. `kit:behavior-placement` Check 3
runs the census.

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

**The threaded argument.** Several methods passing the same argument to each
other — class methods, or private instance methods handing it down a chain. That
argument is the `initialize` of an object that does not exist yet, and the methods
threading it are its instance methods. Where they are already instance methods of
some object, the argument is state that object never named: it gets built at the
top of the chain and carried by hand, one parameter at every hop, because there is
nowhere for it to live.

**The first-parameter receiver.** A class method whose first parameter is the
record it operates on is an instance method that never moved onto the instance.

**Reaching back to the class.** Repeated `self.class.` inside instance methods
means behavior parked at class level that the instance needs. A handful is
noise; dozens is one class living as two.

**The doubled name.** The same name defined twice — class and instance, or
twice at one level — and especially with differing signatures: two things are
wearing one name.

**The unearned construction.** An alternate constructor resorting to
`allocate`, `send(:initialize_…)`, or a mode flag, because the real
`initialize` already claimed the signature: either two objects are in here, or
the state was described wrong.

**The duplicated answer.** A method that recomputes something the application
already establishes elsewhere forks the definition, and the two copies diverge
on the first change. Recomputing from a serialized form — HTML, JSON, CSV
headers — what the application already loaded is the usual case.

**The fixed-key hash.** A method returning a hash whose keys are known when the
method is written is a class that was never named — its keys are the methods it
would have had. The cost lands at every call site: readers key into it by
symbol, `.to_s` defensively because nothing guarantees a type, and no name for
the thing survives the assignment. Section 1's chaining property does not catch
this, because a hash is a legal terminator; the tell is that the keys are
literal, not that a hash came back. When the keys are computed rather than
literal, the next count applies.

**The keyed lookup handed out raw.** A method returning a hash the caller
dereferences by a key it builds itself — `rates[[zone_id, weight_class]]`.
Sibling of the fixed-key hash, and the reason that count's "keys are literal"
tell walks past it: the keys are computed, so nothing looks hardcoded. The cost
is worse, not better — the caller now knows the key's shape and order as well as
the value's, every call site restates that contract, and a wrong key yields `nil`
rather than an error. The fix is not a new class; the object already exists and
was discarded. Keep the hash private and add the question:
`rate(zone_id, weight_class)`.

**The unheld namespace.** A class whose returns make sense to only one caller,
filed under the namespace of the data it reads rather than the one it serves.
The tell is the return type: ask what a caller from the namespace it currently
sits in would do with the value. If nothing there would ever want it, the class
is filed under its input instead of its owner.

**The loop that produces and consumes.** A loop whose body creates something and
then feeds it to a second operation — a record created, then its children built
from it. Tell: a local assigned inside the block and then passed to something that
writes further records. Building a record, mutating it, and saving it is one
operation on one object — that is not this count, and a loop doing only that is
correct. Two passes over the collection, or two methods, say the same thing with a
failure boundary a reader can state: all of the first, then all of the second.
Where it shows up first is the spec — the second operation cannot be exercised
without driving the first.

This is the only count about the inside of a method body. It is here because the
shape survives every other check: arity, naming, and placement can all be correct
while the body still interleaves two operations that had no reason to be
interleaved.

**The deletion test.** Imagine the object gone. If the complexity vanishes, it
was a pass-through. If it reappears at every caller, it earns its place.
Applies to anything being proposed as much as to anything already written.

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
- **Framework conventions are not smells.** Callbacks, scopes, concerns,
  validations, and generated methods are the language being written in. What
  they hold is scorable; that they exist is not.
- **More files is not depth, and neither is fewer.** What a caller has to learn
  is the measure.

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
shallow — or proposing to move the calculation into it — misreads the
architecture.
