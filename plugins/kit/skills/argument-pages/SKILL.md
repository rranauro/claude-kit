---
name: argument-pages
description: Build a self-contained HTML page that argues one technical position from verified evidence — schema, queries, call sites — for a reviewer to read and act on. Use when a review, design comparison, or schema proposal needs more than terminal scrollback, or when another skill needs the evidence-page format.
---

# Argument Pages

A page that makes **one** technical argument to **one** reader who can act on it:
a reviewer deciding whether to merge, a colleague deciding whether to keep their
approach, a team deciding whether a column earns its place. Not a report, not
documentation. It has a thesis and it defends it.

`artifact-design` owns the visual craft — load it before writing the file and
don't restate it here. This skill owns what goes on the page, and what may not.

## The rule that makes it worth reading

**Nothing on the page is asserted from memory.** Every claim is one of:

- a `file:line` you opened
- output you actually ran, pasted
- a row from the schema you read

If the argument contains a query, you ran it and the page shows what it emitted,
reformatted only for line breaks. If you claimed a method has three callers, you
grepped. If you claimed a column has no readers, you searched for it and the page
says how many you found.

This is the entire value. A colleague can dismiss an opinion; they cannot dismiss
their own code read back to them. The moment one code block is hand-written and
merely plausible, the reader has to verify all of them, and the page is worth
less than a paragraph in chat.

Say so on the page — *"verified against the real schema on Rails 8.0.5"* — and
name the two or three facts the verdict rests on, so a reader who wants to
re-check knows where to look.

## Six moves

Not sections to fill in. Skip what this argument doesn't need.

**1 — The verdict, before the evidence.** Three or four short claims across the
top, each with its call (*"Yes — from four columns"*) and one line of why. A
reader who stops here still has your answer. Bury the verdict and they will skim
the middle and invent one.

**2 — The objects.** Whatever the argument is about, drawn: tables and keys,
classes and their callers, the state machine. This is where the reader builds
the model they need for move 4. See [ENTITY-DIAGRAM.md](ENTITY-DIAGRAM.md) —
and do not reach for mermaid.

**3 — The key insight, isolated.** One panel, set apart, holding the thing the
argument turns on. If it reduces to four column names, make it four chips in a
row. This is the sentence the reader repeats to someone else.

**4 — A worked example, with real-looking rows.** The highest-value move and the
one most often skipped. Invent concrete data — named suppliers, real dates,
actual amounts — and walk it through. Mark what is in, what is out, and why.
Land on one specific answer.

Choose the data so it carries a second lesson: make the naive approach visibly
get it wrong, so the reader watches the failure instead of being told about it.

**5 — The mechanism, in stages.** Code built up in numbered moves with a line of
prose each, not dropped as one block. Then the emitted output underneath.

**6 — What to do.** Numbered, imperative, a sentence of why each. Include what
you are *not* recommending, and what you deliberately left open — a page that
resolves every question reads as advocacy, and the open ones are exactly where
the reader's judgment is wanted.

## Where honesty earns the argument

The page is a persuasion device, so its defenses are load-bearing:

- **Give the strongest counter-argument its own heading**, not a hedge in a
  subordinate clause. If a case your recommendation doesn't cover exists, it gets
  a section.
- **Credit what the proposal got right**, specifically, before the objection. A
  page that only attacks gets read as a verdict on the author.
- **Keep verified and inferred visibly apart.** *"I confirmed both"* and *"that's
  a product call"* are different sentences and must not blur into each other.
- **Number nothing that isn't a sequence.** Recommendations in dependency order
  earn numbers; findings and diagram sections don't.
- **Attribute the standing rule you're applying.** If the reader has a stated
  principle and your argument turns on it, quote it back — the page is then
  measuring their proposal against their own bar, not yours.

## Self-contained, always

**No CDNs.** A published artifact runs under a CSP that blocks every external
host except Google Fonts: a Tailwind or Mermaid `<script src>` silently does
nothing and you ship a blank page. Inline all CSS and JS. Fonts come from
`fonts.googleapis.com` with a real fallback stack, or not at all.

The constraint holds for a local file too — a reviewer opening it offline, or
someone finding it in the repo in two years, gets whatever the file contains and
nothing else.

**Destination.** Publish as an artifact when the tool is available; the reader
gets a link rather than a path. Otherwise write it into the project's `plans/`
directory, never a temp path. Either way the source file stays in the repo so
the page can be regenerated and re-published to the same URL.

**Pair it with a plan file.** The page argues; a markdown file in `plans/`
carries the same conclusion plus the verified code, the file:line citations, and
the open questions. The page is for the colleague, the plan file is what survives
a context clear.

## Not findings

- **Length.** One argument across six moves is not bloat. Cutting the worked
  example to save space removes the part that actually convinces.
- **Building a page for a one-line answer.** If the argument fits in a paragraph
  in the terminal, write the paragraph. This is for arguments whose evidence is
  spread across files the reader would otherwise have to open themselves.
- **Prettiness.** Load `artifact-design`, follow it, move on. Time spent on
  visual identity is time not spent verifying a claim.
