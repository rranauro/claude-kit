---
name: asking-a-human
description: The axis for a question a pass puts to a person — the register it is written in, the reach it carries as evidence, and what is not a finding. Use when a pass is about to ask a person to decide — parking the question on an issue, or asking it out loud mid-run — or when another skill needs the reach vocabulary.
---

# Asking a Human

The axis for scoring **a question put to a person**. This is vocabulary and
checks, not a procedure: it gives whatever step is about to ask something to
rank its own question against, and something an adversarial pass can check
rather than argue.

`kit:park` owns *what happens* when a pass stops — the comment, the label, the
worktree, the report. This owns *whether the question is fit to ask*. Neither
decides that a stop is warranted; the invoking command owns that.

A question that fails these checks is not asked as written. Rewrite it, or —
where the checks show the answer was already available — answer it yourself and
carry on.

## 1 — The register is the reader's, not the pass's

A pass writes in the register it was working in: seams, class names, method
names, line numbers. The reader's register is the application — which ways into
the system this touches, and what changes for someone using one of them
depending on how the question is answered.

**Translate before asking.** Re-deriving one register from the other is work the
reader has to do before they can answer, and the pass was in a better position
to do it — it had the code open.

Three checks, each answerable by reading the question:

**It states a decision, not a symptom.** The reader is choosing, so the question
carries the choice. *"The token table moved out of the asset record — does the
approach still hold, or is the placement now different?"* A question that only
reports what went wrong leaves the reader to work out what is being asked.

**Every option is stated, and stated as an outcome.** Two options named in
domain terms beat an open question in wire terms. A reader who has to infer the
alternatives is inferring the question.

**A symbol appears only where the reader would name it too.** A file path, a
class name, or a line number is fine as corroboration — as the *whole* question
it is the register failure with evidence attached. The test is not whether
symbols appear; it is whether removing them leaves a question that still says
what is being decided.

This is the one statement of the register rule. `kit:park` holds its comment to
it by citation, and `kit:writing-tickets` states the ticket-writing form of the
same instinct — domain vocabulary over wire vocabulary in an acceptance
criterion, for a reader who is a future implementer rather than a person being
asked now.

## 2 — The reach is the evidence

A question whose *reach* was never stated is a question nobody can situate. A
decision that materially affects a path everyone travels and one about a path
nobody has taken since it shipped arrive looking identical, and sorting them is
the reader's job — which they cannot do from the question alone.

**Reach** is the set of entry points that get to the thing being decided. An
**entry point** is a path by which work enters the system: an upload, a
generated response, an external client, a command. Not a caller — a caller is
the code symbol that invokes something; an entry point is the way in that
reaches it. `CONTEXT.md` carries both terms.

**Establish it from source.** The entry points are enumerable: follow the
callers outward until each chain terminates in something outside the system's
own code. That walk is the evidence, and it is bounded — a handful of lookups,
not a survey.

**State it in the question**, as its own line, in the reader's terms:

> Reach: the theme editor's token panel and the nightly CSS export both read
> it; nothing else does.

**Weighting is the reader's.** Whether any of those paths is travelled, how
often, or by whom is not established from source, and no pass asserts it. The
pass supplies the paths; the reader supplies what they are worth. A question
that arrives already weighted — *"this is on a critical path"* — has answered
the half of the question it had no evidence for.

## 3 — When the reach cannot be found

**"I searched and could not determine what reaches this" is a valid answer**,
and asking with it is correct. It is not an omission and it is not a failed
check — it is a finding about the code, and often the most useful line in the
question.

Something that nothing statically declares reaching is usually reached some
other way: a dynamic dispatch, a string-named callback, a config key, a
scheduler, an external caller nobody in this repo declares. That is frequently
the defect the question was circling.

Carry it to the reader in three parts:

**What was searched.** The symbol, the strings, the directories. Enough that the
reader can tell a thorough walk from a shallow one, and enough that they can
name the search that would have found it.

**What that leaves open.** The reach is unestablished, so the weighting the
reader would have applied has nothing to apply to.

**That it was learned, not skipped.** State it as a result — *"nothing in the
repo declares a path to this"* — rather than as an apology for a missing
section.

This reaches the reader **in the question**, never in the observation store.
`kit:observations` is for a pass closing while holding something the ticket did
not ask for, and it stops nothing; an unfindable reach is load-bearing for the
decision being put to someone right now.

## 4 — What is not a finding

Raising any of these is the failure this axis exists to prevent.

- **Nothing observable differs between the answers.** If both options produce
  the same behavior at every entry point the walk found, there is no decision —
  decide it yourself and move on. This is the most common way a question that
  passes every other check still should not be asked.
- **A reach that was not found is never invented.** Section 3 is the answer, and
  a plausible-sounding entry point written to fill the line is worse than the
  blank it replaced.
- **The entry points are never weighted.** Listing them is the whole of the
  evidence; ranking them is the reader's, and a pass that ranks them is
  answering the question it was asking.
- **A question the plan, the acceptance criteria, or the project's own rules
  already answer** is not a question. `kit:park`'s "Never park to avoid
  thinking" and `/kit:design`'s "Never park on" list are the standing statements
  of this; neither is restated here.
- **An edge case that cannot name the input and the path reaching it** is not
  raised at all. `kit:grilling` owns that rule.
- **A missing preference is not a decision.** "The user might want to weigh in"
  describes every question ever asked.

The check that settles it: **name what changes for someone at one of the entry
points you found, depending on the answer.** A question that can name neither
the person nor the change is not ready to ask.
