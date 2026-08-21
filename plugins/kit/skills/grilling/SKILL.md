---
name: grilling
description: Pressure-test a plan, decision, or idea by asserting what is true about it and confirming agreement, raising a decision only where one genuinely exists. Use when the user wants a direction or a ticket's boundary checked before committing to it, or uses any 'grill' trigger phrases.
---

Pressure-test a converged direction by **stating what you take to be true and
confirming the user agrees**. Most of what a design pass leaves open is not
actually open — it has one right answer that the preceding steps already
determined. Asserting it and being corrected is faster than asking, and it
leaves the user with something to react to instead of a quiz to sit.

The work is finding the places where the direction is wrong or genuinely
undecided, not producing questions. A pass that generates questions to look
thorough costs the user attention and the model context, and buys nothing.

## Fence it first

Before anything else, state in one or two sentences what this change builds:
from the acceptance criteria if there is a ticket, otherwise from what the user
asked for. That statement is the fence.

Anything outside it goes on the **Parked** list. Parking is the default for
adjacent work, future work, and anything the user mentioned in passing. A
remark about what might matter later is a remark, not a decision to make now;
never convert one into a question. Nothing leaves the Parked list without the
user asking for it.

Never use `AskUserQuestion` to raise scope. Presenting options turns a
non-question into a decision the user is obliged to make. Out-of-scope
observations reach the user as a sentence they can ignore.

## Assert, don't interrogate

Work through the direction and state what follows from it. Each assertion is
something you believe and are prepared to be wrong about — carrying the
evidence that makes it checkable: a `file:line`, a project rule, a count, an
acceptance criterion.

```
✅ **A1** — <what you take to be true>
   <the evidence: file:line, the rule, the count>
```

The user confirms, corrects, or ignores. A correction reshapes the rest and you
restate; a confirmation is done, not a prompt for the next question about it.

## Getting the facts an assertion needs

When an assertion rests on a fact you do not have, **ask the user whether they
already know it.** They usually do, and they can answer in a line what a search
would spend minutes and a lot of context reaching.

- If they know it, take it and confirm it back as part of the assertion it
  supports, so a misremembered fact surfaces before it is built on.
- If they do not, go and find it yourself — dispatch a sub-agent if it is a
  real search. Do not hand the lookup back to them.

Asking "do you know X?" is not the same as asking them to do your work; asking
them to go and look is. An assertion you can neither support with evidence nor
confirm with the user is not an assertion — drop it.

## Raise a decision only where one exists

Most branches have one best answer. Stating it as one of two or three
"alternatives" is noise dressed as rigour — it asks the user to re-derive a
conclusion you already reached.

A decision earns a question only when it commits to one of the following. Each
is checkable against the change itself; a category with no check behind it is
taste, and does not earn a question.

**Performance — does the work happen once, or once per row?** The direction
puts a query, an HTTP call, or an AI call inside a loop, a render path, or
something running on every request. Count the calls per request. If the answer
is "one" either way, there is no question here.

**Testability — can you construct it and call it?** Write the first line of the
test in your head. If reaching the behavior means going through the network,
the clock, an AI response, or a whole controller, that is the finding. If it is
`Thing.new(…).method`, there is no question here.

**Maintainability and extensibility — what does the next change touch?** Name
the next change that is actually likely — a second format, a second provider,
one more field — and count the files it edits. Two or more places that must
change together when one fact changes is the finding. "It might be hard to
extend later" without a named next change is not.

Nothing else on the tree is worth a user's time.

When one does earn it, present the direction and the single best alternative —
what it buys, what it costs, and which you recommend. Not a menu.

```
❓ **Q1** — <the decision, in one line>

   <what the current direction does, and its consequence>
   <the one alternative, and its consequence>

➡️ <your recommendation>
```

Let the user decide whether a new direction is required. Do not decide it for
them, and do not keep asking once they have.

## Do not manufacture edge cases

Hunting for hypothetical failures is where this pass goes wrong. It is
expensive, it reads as thoroughness, and it usually surfaces cases the code
cannot reach.

An edge case is raisable only if you can **name the input and the path that
gets there** in the code or spec in front of you. If you cannot, it is not a
finding — say nothing rather than raising it hedged.

The same test applies to any concern: **name the caller it costs, or the change
it makes harder.** A concern that can name neither does not go in the round.

## Rounds

Do a round of assertions and any earned questions together, then wait. Answers
and corrections reshape what follows; restate and go again only if something
changed. Scale to the change — a one-file change gets a few assertions, not a
mapped subsystem.

An assertion or question whose answer depends on something still open in this
round belongs to a later round.

## Stopping

Done when nothing remaining can change the implementation — not when the tree
is exhausted. The tree of any change extends into every adjacent system, so
exhausting it is not a reachable stop condition. A round that produces only
confirmations is the signal to stop, not to look harder.

Then report the Parked list, unnumbered, as plain observations. Do not act on
the design until the user confirms you have reached a shared understanding.
