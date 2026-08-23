# HTML Report Format

The architectural review is rendered as a single self-contained HTML file in the
repository's `plans/` directory — never a temp path. Tailwind and Mermaid both
come from CDNs. Mermaid handles graph-shaped diagrams reliably (who constructs a
class and who calls it is exactly that); hand-built divs and inline SVG handle
the more editorial visuals. Mix the two: don't lean on Mermaid for everything,
it'll start to look generic.

## Scaffold

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Architecture review for {{repo name}}</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script type="module">
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
      mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "loose" });
    </script>
    <style>
      /* small custom layer for things Tailwind doesn't cover cleanly:
         dashed call edges, hand-drawn-feeling arrow heads, etc. */
      .census { stroke-dasharray: 4 4; }
      .cost { stroke: #dc2626; }
      .owned { background: linear-gradient(135deg, #0f172a, #1e293b); }
    </style>
  </head>
  <body class="bg-stone-50 text-slate-900 font-sans">
    <main class="max-w-5xl mx-auto px-6 py-12 space-y-12">
      <header>...</header>
      <section id="candidates" class="space-y-10">...</section>
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
in a `text-xs font-mono` gutter so the order is visible while scrolling.

## Candidate card

The diagrams carry the weight. Prose is sparse, plain, and uses the terms from
`kit:rails-codebase-design` without ceremony.

Each candidate is one `<article>`:

- **Rank + title**: short, names the reshaping (e.g. "Fold order intake back onto
  Order").
- **Badge row**: recommendation strength (`Strong` = emerald, `Worth exploring` =
  amber, `Speculative` = slate), plus a tag for which count fired
  (`arity`, `threaded argument`, `first-parameter receiver`, `fixed-key hash`,
  `duplicated answer`, `unheld namespace`, `doubled name`).
- **Files**: monospaced list with `file:line`, `font-mono text-sm`.
- **Count**: one line, with the number in it — "arity of 6, drawn from 3
  aggregates". The number is the evidence; don't paraphrase it away.
- **Cost**: the caller it costs, or the change it makes harder. Rendered
  prominently — this is the card's claim, and a card without one does not ship.
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

### Mermaid graph (the workhorse for the call-site census)

Use a Mermaid `flowchart` or `graph` when the point is "these four callers all
construct it, and only one of them uses what it reads." Wrap it in a
Tailwind-styled card so it doesn't feel parachuted in. Style with classDef to
colour the costly edges red and the owning model dark.

```html
<div class="rounded-lg border border-slate-200 bg-white p-4">
  <pre class="mermaid">
    flowchart LR
      A[OrdersController] --> B[Order::Intake.for_order]
      C[ImportJob] --> B
      B --> D[(Order)]
      classDef cost stroke:#dc2626,stroke-width:2px;
      class B cost
  </pre>
</div>
```

### Hand-built boxes-and-arrows (when Mermaid's layout fights you)

Classes as `<div>`s with borders and labels. Arrows as inline SVG `<line>` or
`<path>` elements positioned absolutely over a relative container. Reach for this
when you want the "after" diagram to feel like one model owning its data with the
extracted class dissolved into it, since Mermaid won't render that with the right
weight.

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
  for headings (`font-serif` works well with stone/slate).
- Colour sparingly: one accent (emerald or indigo) plus red for the cost and
  amber for warnings.
- Keep diagrams ~320px tall so before/after sits comfortably side by side without
  scrolling.
- Use `text-xs uppercase tracking-wider` for class labels inside diagrams, so
  they read as schematic, not as UI.
- The only scripts are the Tailwind CDN and the Mermaid ESM import. The report is
  otherwise static: no app code, no interactivity beyond Mermaid's own rendering.

## Top recommendation section

One larger card. The first-ranked candidate, one sentence on why it leads, anchor
link to its card. That's it.

## Tone

Plain English, concise, but the nouns and verbs come straight from
`kit:rails-codebase-design`. Concision is not an excuse to drift.

**Use exactly:** model, concern, value object, service, namespace, aggregate,
accessor, construction arity, call site, derivation.

**Never substitute:** module, unit, component (for class) · interface, API (for
the constructor and public methods) · seam, boundary (for namespace) · layer,
wrapper.

**Phrasings that fit the style:**

- "`Order::Intake` takes the record and pulls what it needs — the dependency
  surface is unpinned."
- "Three class methods thread `page` through each other; `page` is the
  `initialize` of the object that doesn't exist."
- "The hash's four keys were always four methods."
- "`Order` already derives this; the class re-parses it out of the serialized
  form."

**Cost lines** name a caller or a change: *"both callers must read `Order` to
know what this depends on"*, *"adding a column changes the parser and the
model"*. Don't write *"easier to maintain"* or *"cleaner code"* — they name
neither, and `kit:rails-codebase-design` §3 says friction that can name neither
is not a finding at all.

No hedging, no throat-clearing, no "it's worth noting that…". If a sentence could
be a bullet, make it a bullet. If a bullet could be cut, cut it. If a term isn't
in the `kit:rails-codebase-design` vocabulary, reach for one that is before
inventing a new one.
