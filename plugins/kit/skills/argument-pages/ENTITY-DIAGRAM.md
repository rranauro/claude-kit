# Entity Diagrams

Hand-built cards, not mermaid. You need to tint one row, badge another, and grey
out a third — that's the argument, and an `erDiagram` gives you none of it.
(Mermaid stays right for flow and sequence, where the layout is real work.)

## What to build

Three parts. The third replaces the connector lines.

**Cards** — one per table or class. Header carries the real name plus a one-line
gloss in plain language (`rfx_providers` — *one supplier's submission to one
PSE*). The gloss is not decoration; it is how a reader who doesn't know the
schema follows the worked example later.

**Bands** — cards grouped into two to four labelled rows that tell the story in
order (*the event* → *where it's banked* → *where it's frozen*). The banding
carries the narrative that arrows would have.

**A relationships table** — from, cardinality, to, meaning. State the edges you
can't draw. Each one gets a sentence, which reads better than an arrow anyway.

## Vocabulary

| Class | Means |
|---|---|
| `.ent` | one table or class |
| `.ent.focus` | the single entity the argument is about — ring, used once |
| `.is-series`, `.is-new` | tinted rows: *this column matters to the argument* |
| `.badge.pk`, `.badge.fk` | structure — neutral accent |
| `.badge.series`, `.badge.new` | argument — semantic colour |
| `.note` | a sentence of argument attached to one column |

Structure badges and argument badges must stay visually distinct, and the badge
vocabulary is one you invented for this page — print a legend under the diagram.

## Markup

```html
<div class="band">
  <div class="band-label">Where the agreement is banked</div>
  <div class="ents">

    <div class="ent focus">
      <div class="ent-head">
        <b>saved_line_item_rate_card_prices</b>
        <span>the agreement — one line, one currency</span>
      </div>
      <ul>
        <li><span class="nm">id</span><span class="badge pk">pk</span></li>
        <li class="is-series">
          <span class="nm">saved_line_item_id</span>
          <span class="badge fk">fk</span><span class="badge series">series</span>
        </li>
        <li class="is-new">
          <span class="nm">previous_rate_card_price_id</span>
          <span class="badge fk">fk</span><span class="badge new">proposed</span>
          <span class="note">self-referential; added by PR #40218</span>
        </li>
      </ul>
    </div>

  </div>
</div>
```

`.note` is `flex-basis: 100%`, so it wraps onto its own line under the column
name — that's what lets a column carry a full sentence without breaking the row.

## CSS

Everything resolves through theme tokens. Never a colour literal here;
`artifact-design` owns how the tokens are defined across the three theme states.

```css
.band       { display: flex; flex-direction: column; gap: .7rem; }
.band-label { font-size: .68rem; font-weight: 600; letter-spacing: .12em;
              text-transform: uppercase; color: var(--faint);
              display: flex; align-items: center; gap: .75rem; }
.band-label::after { content: ""; flex: 1; height: 1px; background: var(--rule); }

.ents { display: grid; grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
        gap: .9rem; align-items: start; }

.ent  { border: 1px solid var(--rule-strong); background: var(--surface);
        border-radius: 2px; overflow: hidden; display: flex; flex-direction: column; }
.ent.focus { border-color: var(--indigo); box-shadow: 0 0 0 2px var(--indigo-soft); }

.ent-head   { background: var(--indigo-soft); border-bottom: 1px solid var(--rule-strong);
              padding: .6rem .75rem .65rem; display: flex; flex-direction: column; gap: .2rem; }
.ent-head b { font-family: var(--mono); font-size: .76rem; color: var(--indigo);
              overflow-wrap: anywhere; }
.ent-head span { font-size: .74rem; font-style: italic; color: var(--muted); }

.ent ul { list-style: none; margin: 0; padding: 0; }
.ent li { display: flex; align-items: baseline; flex-wrap: wrap; gap: .3rem .4rem;
          padding: .42rem .75rem; border-bottom: 1px solid var(--rule);
          font-family: var(--mono); font-size: .735rem; color: var(--ink); }
.ent li:last-child { border-bottom: 0; }
.ent li.is-series  { background: var(--teal-soft); }
.ent li.is-new     { background: var(--amber-soft); }
.ent li .note { flex-basis: 100%; font-family: var(--body); font-size: .75rem;
                font-style: italic; color: var(--muted); }

.badge        { font-size: .56rem; font-weight: 600; letter-spacing: .08em;
                text-transform: uppercase; padding: .08rem .32rem;
                border-radius: 2px; border: 1px solid currentColor; white-space: nowrap; }
.badge.pk     { color: var(--indigo); background: var(--indigo-soft); }
.badge.fk     { color: var(--faint);  border-color: var(--rule-strong); }
.badge.series { color: var(--teal);   background: var(--teal-soft); }
.badge.new    { color: var(--amber);  background: var(--amber-soft); }
```

## Rules

**Only the columns the argument needs.** A card is not a schema dump — `id`, the
foreign keys in play, and whatever the argument turns on. The reader has
`schema.rb` for the rest.

**Tint rows, not cards.** A tinted row says *this column matters*. The
card-level `.focus` ring is for the one entity the whole page is about.

**Wide content scrolls in its own container.** `overflow-x: auto` on a wrapper;
the page body never scrolls sideways. The auto-fit grid handles the cards, but
the relationships table needs it.

**Caption the takeaway, not the object.** *"The four columns marked series define
one supplier's price history…"* beats *"Entity relationship diagram."*
