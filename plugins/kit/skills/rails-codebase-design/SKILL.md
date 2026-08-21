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

Six properties. Each is checkable by reading the file, and an approach either
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

An object with all six is legible from its call site. Someone planning a change
can tell what it holds and what it answers without opening it — which is the
whole point of the axis.

## 2 — What to count when it isn't

Counts, not preferences. Each states what the number means and stops there.

**Construction arity.** More than three arguments, or arguments drawn from more
than two aggregates: a structure nobody has named is being assembled at every
call site. The missing structure is the finding, not the length of the list.

**The threaded argument.** Several class methods passing the same argument to
each other: that argument is the `initialize` of an object that does not exist
yet, and those methods are its instance methods.

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

**The unheld namespace.** A class whose returns make sense to only one caller,
filed under the namespace of the data it reads rather than the one it serves.
The tell is the return type: ask what a caller from the namespace it currently
sits in would do with the value. If nothing there would ever want it, the class
is filed under its input instead of its owner.

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
