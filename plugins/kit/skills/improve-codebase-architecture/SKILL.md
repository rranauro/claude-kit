---
name: improve-codebase-architecture
description: Scan a codebase for misshapen objects and present them as a visual HTML report in plans/, ranked strongest to weakest. The report is the deliverable.
disable-model-invocation: true
---

# Improve Codebase Architecture

Surface architectural friction across an area and propose **reshaping
opportunities** — refactors that turn a class a caller must open into one they
can read from the call site. The aim is legibility for whoever plans the next
change, human or agent.

**The HTML report is the endpoint.** A run that produces a ranked report and
stops has succeeded. This command surveys; it does not design, and it does not
need the user to pick anything for the run to have been worth it.

This command is _informed_ by the project's domain model and built on the
project's own design vocabulary:

- Invoke `kit:rails-codebase-design` for the axis — the seven properties of a
  well-shaped object, the counts that fire when one isn't, and the explicit list
  of what is **not** a finding. Use its terms exactly: model, concern, value
  object, service, namespace, aggregate, accessor, construction arity. Don't
  drift into "module," "interface," "seam," or "adapter" — this codebase is
  Rails, and a vocabulary that calls a function and a tier-spanning slice the
  same word gives the report nothing checkable.
- Invoke `kit:behavior-placement` when a candidate's *owner* is in question —
  whether behavior belongs on the model, in a value object, or in a service.
  Used as a filter here, not as a design step.
- The domain language in `CONTEXT.md` names the concepts; ADRs in `docs/adr/`
  record decisions this command should not re-litigate.

Those two skills supply vocabulary and checks, not a procedure. Keep the survey
at survey altitude: a candidate is a *direction* worth a day of someone's
attention, not a designed class.

## Process

### 1. Explore

**Scope before you scan — YAGNI.** Reshaping a class pays off by making future
changes to it easier, so put extra weight on the parts of the codebase that have
recently changed. Decide *where* to look before you look:

- If the user named a direction — a model, a subsystem, a pain point — take it,
  and skip the inference below.
- Otherwise, walk back a good stretch of the commit history (`git log --oneline`)
  to find the codebase's hot spots — the files and areas that keep coming up —
  and let those paths pull your attention first. If the changes are scattered
  with no clear hot spot, widen the net.

Read the project's domain glossary (`CONTEXT.md`) and any ADRs in the area
you're touching first.

Then spawn sub-agents to walk the codebase. Look for the counts in
`kit:rails-codebase-design` §2, because each one either fires or doesn't and
carries a file and a line:

- **Construction arity** — more than three arguments, or arguments from more
  than two aggregates.
- **The threaded argument** — several methods passing the same argument to each
  other, class methods or private instance methods down a chain.
- **The first-parameter receiver** — `Model.do_thing(record)`.
- **Reaching back to the class** — repeated `self.class.` inside instance methods.
- **The doubled name** — one name defined twice, especially with differing
  signatures.
- **The unearned construction** — an alternate constructor using `allocate`,
  `send(:initialize_…)`, or a mode flag.
- **The duplicated answer** — a method recomputing from a serialized form what
  the app already hydrates.
- **The fixed-key hash** — a returned hash whose keys are literal.
- **The keyed lookup handed out raw** — a returned hash the caller dereferences
  by a composite key it builds itself. Fires at the call site, not the producer,
  so a sub-agent reading only the class that returns it will miss this one.
- **The loop that produces and consumes** — a loop creating a record and then
  passing it to something that writes further records.
- **The unheld namespace** — a class filed under the data it reads rather than
  the caller it serves.

Cast wide here. Cheap counts over a large surface is what makes the report worth
reading; a scan that returns two candidates has under-searched.

### 2. Filter and rank

Every count is a lead, not a finding. Three gates, applied in order, and then
the ranking.

**The deletion test.** Imagine the object gone. If the complexity reappears at
every caller it earns its place; if it vanishes, it was a pass-through.

**Name the caller it costs, or the change it makes harder.** Friction that can
name neither is not a finding and does not reach the report. This is the closer
that settles a candidate, and it is also what its card leads with.

**Discard, don't weaken, anything on the not-a-finding list** (§3). These are
this scan's characteristic false positives, and this codebase's conventions
positively require several of them:

- "It isn't injected" / "the database is a dependency" / "it needs testing
  without the DB."
- "This method changes its own record."
- Callbacks, scopes, concerns, validations, generated methods — the language,
  not a smell.
- File count in either direction. What a caller has to learn is the measure.
- A Stimulus controller that renders what the server calculated. It is complete,
  not thin (§4).

A candidate whose only support is one of those is not a weaker candidate; it is
not a candidate.

Two lightweight placement questions decide how a survivor is *framed*, and
neither is a design pass:

- **Does the app already derive this?** (`kit:behavior-placement` Check 2.) If
  so, the candidate is "reuse the existing derivation" — name it, and say so on
  the card.
- **Does this want an owner rather than a new class?** (Check 1.) Fold onto the
  model, inline, or delete belongs on the card ahead of "extract" whenever it
  fits. The lowest-value candidate in any report is one that relocates a file.

**Then rank, strongest to weakest.** Strength is how much a change here helps
the next change: how many callers pay the cost, how often the area changes (the
hot spots from step 1), and how confident the count is. That order is the report
order.

**A named target gets its own section, not a rank position.** Ranking is global,
and global ranking always buries the specific: a rule duplicated across five
callers outranks a defect confined to one method every time, so when the user
named a file, class, or diff, its own findings sink below the cut and they read a
report that never mentions the thing they asked about. So split the report when
the invocation named a target — that target's findings first, in their own
section, ranked only among themselves, and reported even when they are weak.
"These counts fired here, these did not" is a real answer to the question that was
asked. The system-wide ranking follows underneath. Label which section a candidate
is in, and never merge the two.

### 3. Present candidates as an HTML report

Write the report into the repository's `plans/` directory, so it sits beside the
plans the other commands write and stays findable weeks later. Resolve the repo
root with `git rev-parse --show-toplevel` from the main checkout, `mkdir -p` the
directory if needed, and write to
`plans/architecture-review-<area>-<YYYY-MM-DD>.html`, where `<area>` is a short
slug for what was scanned (`plans/architecture-review-themes-2026-08-23.html`).
Same-day reruns over the same area overwrite; a different area gets its own file.

`plans/` is gitignored and symlinked into every worktree by `/kit:start-ticket`,
so the report survives the session without landing in the repo. Add `/plans` to
`.gitignore` if it isn't there already. Never write the report to `$TMPDIR` or
any other path outside the project — a hashed temp path is unrecoverable the
moment the terminal scrollback is gone, which is the same as not writing it.

Open it for the user — `xdg-open <path>` on Linux, `open <path>` on macOS,
`start <path>` on Windows — and tell them the path relative to the repo root.

**Candidates appear in rank order, strongest first**, each carrying its
`Strong` / `Worth exploring` / `Speculative` badge, so the page reads as a
ranking from top to bottom rather than a list to be searched.

The report uses **Tailwind via CDN** for layout and styling, and **Mermaid via
CDN** for diagrams where a graph/flow/sequence reliably communicates the
structure. Mix Mermaid with hand-crafted CSS/SVG visuals: use Mermaid when
relationships are graph-shaped (who constructs a class and who calls it is
exactly that), and hand-built divs/SVG when you want something more editorial.
Each candidate gets a **before/after visualisation**. Be visual.

For each candidate, render a card with:

- **Files** — which files and classes are involved, with `file:line`
- **Count** — which count from §2 fired, and its number ("arity of 6"; "three
  class methods threading `page`"; "a hash with four literal keys")
- **Cost** — the caller it costs, or the change it makes harder. Mandatory; a
  card without one does not ship
- **Solution** — one sentence on what would change, in the shape it would take:
  fold onto the model, reuse the existing derivation, name the structure
- **Before / After diagram** — side-by-side, custom-drawn
- **Recommendation strength** — the badge, matching its rank position

Where a candidate proposes a **new class**, add one monospaced line: the
`initialize` it would take. Nothing more — no method list, no implementation.
Candidates described in prose all read as reasonable, and two whose
constructors would be identical are one candidate; the line is what makes the
difference visible. If it cannot be written — if what the class takes is "the
record, and it'll pull what it needs" — that is the finding: this is a method on
whatever owns the record, and the card says that instead.

End the report with a **Top recommendation** section: the first-ranked
candidate, one sentence on why it leads, and an anchor to its card.

**Use CONTEXT.md vocabulary for the domain, and `kit:rails-codebase-design`
vocabulary for the shape.** If `CONTEXT.md` defines "Order," talk about the
`Order` model and the `Order::Intake` value object — not "the FooBarHandler,"
and not "the Order intake module."

**ADR conflicts**: if a candidate contradicts an existing ADR, only surface it
when the friction is real enough to warrant revisiting the ADR. Mark it clearly
in the card (e.g. a warning callout: _"contradicts ADR-0007 — but worth
reopening because…"_). Don't list every theoretical refactor an ADR forbids.

See [HTML-REPORT.md](HTML-REPORT.md) for the full HTML scaffold, diagram
patterns, and styling guidance.

### 4. Stop, and offer

Report the path and the ranking in two or three lines. Then stop. The run is
complete, and the user may well be done — a survey they read and act on next
month is the normal outcome.

Offer, in one line each, and only act on what the user picks:

- **Explore a candidate?** Invoke `kit:grilling` on it: state what it commits
  to — what state the object holds, what moves onto the model, which callers
  change — and get agreement. Then hand to `/kit:design` for the *how*; it
  re-runs placement and shape against the real code and writes the plan. Don't
  walk into design from here on your own.
- **File one?** `kit:writing-tickets` turns a card into an issue that keeps its
  problem statement and leaves the mechanism open.

Neither is a step in this command. Nothing further happens without the user
asking.

Two side effects are worth doing inline if the conversation continues:

- **A candidate names a concept not in `CONTEXT.md`?** Add the term. Create the
  file lazily if it doesn't exist.
- **User rejects a candidate with a load-bearing reason?** Offer an ADR, framed
  as: _"Want me to record this as an ADR so future architecture reviews don't
  re-suggest it?"_ Only offer when the reason would actually be needed by a
  future explorer to avoid re-suggesting the same thing — skip ephemeral reasons
  ("not worth it right now") and self-evident ones.

`kit:domain-modeling` owns both formats — glossary entries in its
`CONTEXT-FORMAT`, ADRs in its `ADR-FORMAT`. Invoke it rather than inventing a
shape here.

## Never

- Make implementation changes. This is a scan and a report.
- Design a candidate in the report. One constructor line is the ceiling.
- Ship a card that can't name the caller it costs.
- Score a class down for anything on the not-a-finding list.
- Propose relocating a file as the finding. Ownership first, layout after.
- Write the report anywhere but the repo's `plans/` directory.
