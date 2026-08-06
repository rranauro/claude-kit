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
offer `/improve-codebase-architecture` — a scan-and-report is a better opening
move than reading files ad hoc.

## Filing tickets

Only when the user says they want tickets, or you ask "want to turn any of this
into tickets?" and they agree. Never slide into it because a direction started
looking good.

**The only decision being made here is whether the ticket exists.** A ticket
states the problem and the intended behavior. It does not settle how to build
it — that question stays open for `/kit:design`, where it gets real scrutiny. Don't
resolve it in passing to make the issue read as finished.

Per ticket: invoke `kit:writing-tickets` and draft **one** issue as a preview — it
owns the format and the leanness rules, do not restate them here. Raise any open
questions specific to that issue, get approval, create it, then move to the next.
Do not batch-create.

Cross-link related existing issues (comments on both sides) when the
relationship surfaces mid-session.

**After each issue is created, ASK whether to run `/kit:design` on it now or defer.**
Default to defer — the issue is the durable artifact, and `/kit:start-ticket` reads
it and re-explores current code. Reach for `/kit:design` now only when the ticket
will be picked up immediately or its shape is genuinely non-obvious.

## Never

- Make implementation changes. This is discussion only.
- Create issues before the user explicitly says they're ready.
- Write a `plans/` file. That's `/kit:design`'s output.
