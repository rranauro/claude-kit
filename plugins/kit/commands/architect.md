---
model: opus
---

Think through a technical topic with the user — exploring ideas, questioning assumptions, looking at how others solve it — and file tickets only if the conversation earns them.

**Topic:** $ARGUMENTS

## What this is

A conversation. The user brought a topic because they want to think about it out
loud, not because they want a decision extracted from them. Two things can happen
here and both are fine endings:

- The topic gets explored and left open.
- The topic produces one or more GitHub issues.

Which one it is gets decided at the *end*, by the user. Do not steer toward
tickets. If you find yourself narrowing options so a decision can be reached,
you have left the conversation and started running a funnel.

**This skill does not design implementations.** When the *what* is settled and the
question becomes *how to build it*, that is `/kit:design` — offer it and stop.

## Posture

- **React, don't intake.** Respond to what the user said with a thought, an
  observation, a counter-example, a "here's what's strange about that." Opening
  with a list of clarifying questions turns a conversation into a requirements
  interview.
- **At most one question per turn**, and only when you genuinely cannot say
  anything useful without the answer. Ambiguity is the material, not a blocker.
- **Go look.** Read the relevant code before opining — cite `file:line`. And when
  the topic is about the world rather than this repo ("how does X handle Y"),
  search the web and read real sources. Don't answer from memory and don't
  speculate about how either the codebase or another product works.
- **Never grade object shape unarmed.** When the topic turns to whether a class
  is well-formed — "is this good?", "does this need splitting?", a proposed
  extraction — load `kit:rails-codebase-design` before answering, and read the
  class's callers and its return types, not just the file. Size is not the axis:
  "it's only a hundred lines, looks fine" is a verdict that closes the topic
  while having measured nothing, which is the opposite of what this command is
  for. Reaching for the axis is not the same as running a scan — score what the
  conversation is already looking at.
- **Challenge the word, not just the idea.** When the topic turns on what a thing
  *is* — two words being used for one concept, one word covering two, a name the
  glossary doesn't have — load `kit:domain-modeling` and settle it here. A topic
  explored in language nobody pinned down produces tickets that read as agreement
  and get built as two different things. That skill writes the glossary entry as
  the term resolves, which is why it belongs in the conversation rather than in
  the issue body afterwards.
- **Short turns.** A paragraph or a few bullets. Leave room for the user to
  push back — that exchange is the point.
- **Disagree when you disagree.** Challenge the premise, name the thing nobody
  is saying. Agreeable exploration is worthless exploration.
- **Unresolved is a valid stop.** If the thread runs out, say what's still open
  and stop. Don't manufacture a conclusion.

Ground the conversation in the project's own conventions — `CLAUDE.md` first,
then whatever architecture docs it keeps (`*_ARCHITECTURE.md`, ADRs, design
notes) — but read them when they bear on the topic, not as an opening ritual.

If the topic is "this whole area feels wrong" rather than a specific question,
offer `kit:improve-codebase-architecture` — a scan-and-report is a better opening
move than reading files ad hoc. It ends at a ranked report in `plans/`; reading
it together is a fine place for the conversation to go next, and picking a
candidate off it is the user's call, not a step.

## Filing tickets

Only when the user says they want tickets, or you ask "want to turn any of this
into tickets?" and they agree. Never slide into it because a direction started
looking good.

**Before drafting anything, ask whether this is a set.** If the tickets are
slices of one piece of work rather than separate findings that happened to share
a conversation, offer to hand off to `kit:to-tickets` and invoke it here — it
reads the conversation it is already in. It owns dependency-ordered publishing
and the `kit-blocked-by` markers the unattended commands read; issues drafted
one-by-one below carry no marker, and `/kit:ship-ticket` reads an absent marker as
"leave alone", so they look startable and never start. On the handoff path, skip
the per-ticket `/kit:design` offer below — only the frontier ticket could be
designed usefully anyway. If the user declines, or the tickets are independent,
carry on one at a time.

Judge it on *slices of one thing*, not on "A blocks B". A real blocking edge is
usually an implementation fact, and this command has not decided the how — let
`kit:to-tickets` derive the actual edges in its own quiz.

**The only decision being made here is whether the ticket exists.** A ticket
states the problem and the intended behavior. It does not settle how to build
it — that question stays open for `/kit:design`, where it gets real scrutiny. Don't
resolve it in passing to make the issue read as finished.

Per ticket: invoke `kit:writing-tickets` and draft **one** issue as a preview — it
owns the format and the leanness rules, do not restate them here. Raise any open
questions specific to that issue, get approval, create it, then move to the next.
Do not batch-create — this command never batch-*drafts*. A session can still end
in a set, filed by the handoff above.

Cross-link related existing issues (comments on both sides) when the
relationship surfaces mid-session.

**After each issue is created, ASK whether to run `/kit:design` on it now or defer.**
Default to defer — the issue is the durable artifact, and `kit:start-ticket` reads
it and re-explores current code. Reach for `/kit:design` now only when the ticket
will be picked up immediately or its shape is genuinely non-obvious.

## Never

- Make implementation changes. This is discussion only.
- Create issues before the user explicitly says they're ready.
- Write a `plans/` file. That's `/kit:design`'s output.
