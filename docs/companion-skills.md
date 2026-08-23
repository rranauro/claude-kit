# Companion skills

I found [Matt Pocock's suite][pocock] about seven months after building this, and
took the nuggets that fit. Three of his skills now live in the plugin as forks,
and one of his ideas was replaced outright.

| Forked as | From | What it supplies |
|---|---|---|
| `kit:improve-codebase-architecture` | `improve-codebase-architecture` | The scan-and-report `/kit:architect` offers when the topic is "this area feels wrong" rather than a specific question. |
| `kit:grilling` | `grilling` | The confirmation pass over a converged direction or a ticket's boundary. |
| `kit:to-tickets` | `to-tickets` | Cutting an epic into dependency-ordered tracer-bullet tickets. |

Each fork carries an `UPSTREAM` file with the sha it was taken at and the `git
diff` incantation for reviewing what upstream changed since, plus the upstream
`LICENSE`. See [commands](commands.md) for what each fork changes. The upstream
copies stay installable and untouched; the commands name the forks explicitly so
the two never get confused for each other.

Install the upstream suite with the [`skills`][skills-cli] CLI:

```
npx skills add mattpocock/skills
```

Claude Code reads global skills from `~/.claude/skills`; the CLI's universal
target is `~/.agents/skills`. If you install for a non-Claude agent, symlink one
to the other so Claude Code sees them. Nothing in this plugin depends on that
install any more — the forks ship with it.

## Why the architecture scan is forked and not called

The upstream scan is built on the vocabulary of its `codebase-design` sibling —
module, interface, depth, seam, adapter — and looks for shallow modules,
extracted-for-testability functions, and leakage across seams. Against a Rails
codebase that combination reliably produces findings this project's conventions
positively require: inject the database, move behavior off the model so it tests
without one, treat a concern or a callback as a smell. There was also no way for
it to conclude a class was already fine.

The fork keeps everything that made it good — the hot-spot scoping, the visual
before/after report, the ADR and `CONTEXT.md` side effects — and changes four
things:

- **The axis.** `kit:rails-codebase-design` replaces `codebase-design`: counts
  that either fire or don't, and an explicit list of what is *not* a finding,
  which is what stops the false positives above at the door.
- **The gate.** *Name the caller it costs, or the change it makes harder* is a
  discard condition, not a nice-to-have. A count is a lead; only the cost makes
  it a candidate.
- **Where the report lands.** The repository's `plans/` directory, ranked
  strongest to weakest — not a hashed `$TMPDIR` path that is unrecoverable the
  moment the scrollback is gone.
- **Where it stops.** At the report. Upstream walks straight from a picked
  candidate into a design conversation; here that is an offer, and the design
  itself belongs to `/kit:design`, which re-grounds in the code before writing a
  plan. The survey has to be worth running for its own sake, because most runs
  end with someone reading it and getting on with something else.

`codebase-design` itself is not forked — `/kit:design` uses
`kit:rails-codebase-design`, written here rather than adopted, for the same
reasons.

The two suites compose rather than compete. `kit:rails-codebase-design` asks what
shape an object should take; `kit:behavior-placement` asks *whose* the behavior
is. And go read the rest of his suite regardless of whether you use this one.

[pocock]: https://github.com/mattpocock/skills
[skills-cli]: https://github.com/vercel-labs/skills
