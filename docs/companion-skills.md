# Companion skills

I found [Matt Pocock's suite][pocock] about seven months after building this, and
took the nuggets that fit. Four of his skills now live in the plugin as forks,
and one of his ideas was replaced outright.

| Forked as | From | What it supplies |
|---|---|---|
| `kit:improve-codebase-architecture` | `improve-codebase-architecture` | The scan `/kit:architect` offers when the topic is "this area feels wrong" rather than a specific question, and the one thing that files an `improve-codebase` ticket. |
| `kit:grilling` | `grilling` | The confirmation pass over a converged direction or a ticket's boundary. |
| `kit:to-tickets` | `to-tickets` | Cutting an epic into dependency-ordered tracer-bullet tickets. |
| `kit:domain-modeling` | `domain-modeling` | Writing the glossary and the ADRs, at the three points where the model actually changes — a term argued in `/kit:architect`, a concept named or an alternative rejected in `/kit:design`, and the two artifacts a `kit:improve-codebase-architecture` scan leaves behind. |

`grill-with-docs` is deliberately not forked: upstream it is a one-line composer
that calls `grilling` and `domain-modeling` back to back, and both halves are
here under their own names. `/kit:architect` and `/kit:design` already run the
grill; reach for `kit:domain-modeling` alongside it when the model itself is what
the conversation is changing.

Each fork carries an `UPSTREAM` file with the sha it was taken at and the `git
diff` incantation for reviewing what upstream changed since, plus the upstream
`LICENSE`. See [commands](commands.md) for what each fork changes. The commands
name the forks explicitly, so a command never reaches the upstream copy — but
the model picking a skill on its own sees both descriptions, and two near-twins
make the fork stop reliably winning.

## Installing the upstream suite

Nothing in this plugin depends on it — the forks ship here. To have the rest of
his suite, install it from a local checkout as a directory marketplace, the same
way this plugin installs:

```
git clone https://github.com/mattpocock/skills ~/dev/mattpocock
claude plugin marketplace add ~/dev/mattpocock
claude plugin install mattpocock-skills@mattpocock
```

`~/dev/mattpocock` is also the default `SKILLS_REPO` that
`scripts/adopt-skill.sh` and `scripts/check-upstream.sh` read, so one checkout
serves the install and the fork review.

Two things break quietly:

- **A pull does not reach the session.** `claude plugin update` compares the
  version in his `plugin.json`, not the files. Run
  `claude plugin update mattpocock-skills@mattpocock` after pulling; a pull that
  did not bump his version changes nothing until one does.
- **The plugin brings the forked skills back.** It installs all of his skills,
  so `mattpocock-skills:grilling`, `:domain-modeling`, `:to-tickets`, and
  `:improve-codebase-architecture` load beside their `kit:` forks — the overlap
  `adopt-skill.sh` exists to remove, and it cannot remove one skill from inside
  a plugin. `skillOverrides` does not apply to plugin skills. A
  `permissions.deny` entry such as `Skill(mattpocock-skills:grilling)` blocks
  the invocation, but is not documented to drop the description from the
  listing; disabling the whole plugin is the only control that does.

The [`skills`][skills-cli] CLI (`npx skills add mattpocock/skills`) installs
loose copies into `~/.agents/skills` instead. `adopt-skill.sh` can retire
individual copies there, but they are fetched from GitHub and go stale against
the checkout the fork review reads.

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
is; `kit:domain-modeling` asks what the thing is *called* and whether the
glossary already answers that. And go read the rest of his suite regardless of whether you use this one.

[pocock]: https://github.com/mattpocock/skills
[skills-cli]: https://github.com/vercel-labs/skills
