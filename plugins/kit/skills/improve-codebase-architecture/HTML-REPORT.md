# HTML Report Format

The architectural review is rendered as a single self-contained HTML file in the
repository's `plans/` directory — never a temp path. Everything it needs is in
the file: one inline `<style>` block for the styling, hand-built divs and inline
SVG for the diagrams. Vary the diagram patterns below rather than drawing every
candidate the same way, or it'll start to look generic.

## Self-contained, always

**No external script and no external stylesheet.** A published artifact runs
under a CSP that blocks every host except Google Fonts — `kit:argument-pages`
states the same rule for its pages — so a CDN `<script src>` silently does
nothing: Tailwind classes style nothing and a Mermaid block prints as source
text. A reader opening the local file offline gets the same broken page. Fonts
may come from `fonts.googleapis.com` with a real fallback stack, or not at all.

## Scaffold

The style block is the report's whole visual vocabulary. Extend it per report;
don't replace it with utility classes.

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Architecture review for {{repo name}}</title>
    <style>
      :root {
        --ground: #fafaf9; --ink: #0f172a; --muted: #64748b; --rule: #e2e8f0;
        --accent: #059669; --cost: #dc2626; --warn: #d97706; --owner: #1e293b;
      }
      body { margin: 0; background: var(--ground); color: var(--ink);
             font: 16px/1.55 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; }
      main { max-width: 64rem; margin: 0 auto; padding: 3rem 1rem; }
      h1, h2 { font-family: ui-serif, Georgia, serif; }
      .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .875rem; }
      .rank { font: .75rem ui-monospace, monospace; color: var(--muted); }
      .card { background: #fff; border: 1px solid var(--rule); border-radius: .5rem;
              padding: 1.5rem; margin: 2.5rem 0; }
      .badge { display: inline-block; padding: .1rem .5rem; border-radius: 999px;
               font-size: .75rem; border: 1px solid currentColor; }
      .badge.strong { color: var(--accent); }
      .badge.explore { color: var(--warn); }
      .badge.speculative { color: var(--muted); }
      .cost { color: var(--cost); font-weight: 600; }
      .reach { color: var(--muted); }
      .adr { background: #fffbeb; border-left: 3px solid var(--warn); padding: .5rem .75rem; }
      .before-after { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
      @media (max-width: 640px) { .before-after { grid-template-columns: 1fr; } }
      .diagram { position: relative; min-height: 320px; border: 1px solid var(--rule);
                 border-radius: .5rem; padding: 1rem; overflow: auto; }
      .box { border: 1px solid var(--ink); border-radius: .25rem; padding: .25rem .5rem;
             font-size: .75rem; text-transform: uppercase; letter-spacing: .05em; }
      .box.owned { background: var(--owner); color: #fff; border-width: 3px; }
      .box.cost, .edge.cost { border-color: var(--cost); stroke: var(--cost); }
      .edge { stroke: var(--ink); fill: none; }
      .edge.call { stroke-dasharray: 4 4; }
    </style>
  </head>
  <body>
    <main>
      <header>...</header>
      <section id="candidates">...</section>
      <section id="top-recommendation">...</section>
    </main>
  </body>
</html>
```

## Header

Repo name, the area scanned, date, and a compact legend: solid box = class,
dashed line = call edge, red arrow = the cost, thick dark box = the model that
owns the data. One line stating the ranking rule — *ordered strongest first* —
so the page reads top-to-bottom. No introduction paragraph. Straight into the
candidates.

## Ordering

Candidates are rendered in rank order, strongest first, and the badge matches the
position. Never group by file, subsystem, or count type: the ranking is the
report's argument, and any other order hides it. Number the cards (`01`, `02`, …)
in a `.rank` gutter so the order is visible while scrolling.

## Candidate card

The diagrams carry the weight. Prose is sparse, plain, and uses the terms from
`kit:rails-codebase-design` without ceremony.

Each candidate is one `<article>`:

- **Rank + title**: short, names the reshaping (e.g. "Fold order intake back onto
  Order").
- **Badge row**: recommendation strength (`Strong` = emerald, `Worth exploring` =
  amber, `Speculative` = slate), plus a tag for which count fired
  (`arity`, `threaded argument`, `first-parameter receiver`, `hidden instance`,
  `fixed-key hash`, `duplicated answer`, `unheld namespace`, `doubled name`).
- **Files**: monospaced list with `file:line`, in `.mono`.
- **Count**: one line, with the number in it — "arity of 6, drawn from 3
  aggregates". The number is the evidence; don't paraphrase it away.
- **Cost**: the caller it burdens, or the change it makes harder. Rendered
  prominently: this is the card's claim.
- **Reach**: the entry points that get to it, on its own line beneath the Cost —
  it is what a chooser ranks on. *Reach lines* below say how to write one.
  A card missing its Cost or its Reach does not ship.
- **Before / After diagram**: the centrepiece. Two columns, side by side. See
  patterns below.
- **Solution**: one sentence. What changes, in the shape it takes — fold onto the
  model, reuse the existing derivation, name the structure.
- **Constructor line** (only when the candidate proposes a new class): one
  monospaced line, the `initialize` it would take. No method list, no body.
- **ADR callout** (if applicable): one line in an amber-tinted box.

No paragraphs of explanation. If the diagram needs a paragraph to be understood,
redraw the diagram.

## Diagram patterns

Pick the pattern that fits the candidate. Mix them. Don't make every diagram look
the same. Variety is part of the point.

### Caller graph (the workhorse for producers and consumers)

Use it when the point is "these four callers all construct it, and only one of
them uses what it reads." Draw it as one inline `<svg>` inside a `.diagram`: a
column of caller boxes on the left, the class in the middle, the owning model on
the right, edges as `<path>`s between them. Colour the costly box and its edges
with `cost`, and give the owning model the `owned` fill. Set a `viewBox` so it
scales with the column rather than overflowing it.

```html
<div class="diagram">
  <svg viewBox="0 0 520 200" width="100%" role="img"
       aria-label="OrdersController and ImportJob both construct Order::Intake, which reads Order">
    <defs>
      <marker id="arrow" viewBox="0 0 10 10" refX="10" refY="5"
              markerWidth="6" markerHeight="6" orient="auto-start-reverse">
        <path d="M0 0L10 5L0 10z" />
      </marker>
    </defs>
    <g font-size="11" font-family="ui-monospace, monospace">
      <rect x="10" y="30" width="150" height="32" fill="#fff" stroke="#0f172a" />
      <text x="85" y="50" text-anchor="middle">OrdersController</text>
      <rect x="10" y="130" width="150" height="32" fill="#fff" stroke="#0f172a" />
      <text x="85" y="150" text-anchor="middle">ImportJob</text>
      <rect x="200" y="80" width="170" height="32" fill="#fff" stroke="#dc2626" stroke-width="2" />
      <text x="285" y="100" text-anchor="middle">Order::Intake.for_order</text>
      <rect x="410" y="80" width="100" height="32" fill="#1e293b" />
      <text x="460" y="100" text-anchor="middle" fill="#fff">Order</text>
    </g>
    <path class="edge cost" d="M160 46 L200 90" marker-end="url(#arrow)" />
    <path class="edge cost" d="M160 146 L200 104" marker-end="url(#arrow)" />
    <path class="edge call" d="M370 96 L410 96" marker-end="url(#arrow)" />
  </svg>
</div>
```

### Hand-built boxes-and-arrows (when the after has one owner)

Classes as `.box` divs with borders and labels. Arrows as inline SVG `<line>` or
`<path>` elements positioned absolutely over the `.diagram`, which is the
relative container. Reach for this when you want the "after" diagram to feel like
one model owning its data with the extracted class dissolved into it — an
`owned` box with the old class drawn inside it, not beside it.

### Constructor bars (good for arity and unnamed structure)

One bar per constructor argument, grouped and coloured by the aggregate it comes
from. Before: six bars in three colours — a structure nobody has named. After:
two bars in one colour, with a caption naming the structure that absorbed the
rest.

### Chain diagram (good for a call site that can't say what it got)

Before: `a = record.method1` with a question mark where the name should be.
After: `a = record.method1.y`, each step a box returning `self` into the next,
terminating in an output format.

### Hash-to-object collapse (good for the fixed-key hash)

Before: a hash literal with its keys listed and call sites keying into it by
symbol. After: the same keys as method names on one box, call sites reading
`.manifest` instead of `[:manifest]`.

## Style guidance

- Lean editorial, not corporate-dashboard. Generous whitespace. Serif optional
  for headings; the scaffold's serif stack works with its stone and slate.
- Colour sparingly: one accent (emerald or indigo) plus red for the cost and
  amber for warnings.
- Keep diagrams ~320px tall so before/after sits comfortably side by side without
  scrolling.
- Use small uppercase, letter-spaced labels for classes inside diagrams — `.box`
  does it — so they read as schematic, not as UI.
- No scripts at all. The report is static: no app code and no interactivity.

## Top recommendation section

One larger card. The first-ranked candidate, one sentence on why it leads, anchor
link to its card. That's it.

## Tone

Plain English, concise, but the nouns and verbs come straight from
`kit:rails-codebase-design` — its §5 and the counts in §2, each with the words it
avoids. Concision is not an excuse to drift.

**Phrasings that fit the style:**

- "`Order::Intake` takes the record and pulls what it needs — the dependency
  surface is unpinned."
- "Three class methods thread `page` through each other; `page` is the
  `initialize` of the object that doesn't exist."
- "The hash's four keys were always four methods."
- "`Order` already hydrates this; the class recomputes it from the serialized
  form."

**Cost lines** name a caller or a change: *"both callers must read `Order` to
know what this depends on"*, *"adding a column changes the parser and the
model"*. Don't write *"easier to maintain"* or *"cleaner code"* — they name
neither, and `kit:rails-codebase-design` §3 says friction that can name neither
is not a finding at all.

**Reach lines** name where the walk came out, in the reader's terms, and stop
there: *"Reach: theme upload and the nightly CSS export; nothing else declares a
path to it"*. When it came out nowhere, say so and say what you looked at:
*"Reach: searched the callers of `TokenTable`, the scheduler config and the
string-dispatch table — nothing in the repo declares a path to it"*. Don't write
*"Reach: critical path"* or *"widely used"* — those weight the entry points,
which §2 reserves for the reader.

No hedging, no throat-clearing, no "it's worth noting that…". If a sentence could
be a bullet, make it a bullet. If a bullet could be cut, cut it. If a term isn't
in the `kit:rails-codebase-design` vocabulary, reach for one that is before
inventing a new one.
