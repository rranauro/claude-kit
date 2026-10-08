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

Not every fork is his. `kit:show-me` comes unchanged from [HumanLayer's
skills][humanlayer]: the visual explainer, user-invoked only.

Each fork carries an `UPSTREAM` file with the sha it was taken at, the local
checkout it was taken from, and the `git diff` incantation for reviewing what
upstream changed since, plus the upstream `LICENSE`. `scripts/adopt-skill.sh`
writes it from whichever checkout `SKILLS_REPO` names, and
`scripts/check-upstream.sh` checks each fork against its own checkout. See
[commands](commands.md) for what each fork changes. The commands name the forks
explicitly, so a command never reaches the upstream copy — but the model
picking a skill on its own sees both descriptions, and two near-twins make the
fork stop reliably winning.

## Installing the upstream suite

Nothing in this plugin depends on it — the forks ship here. To have the rest of
his suite, install it as a plugin whose skills run only when named
(`/mattpocock-skills:tdd`) and are never picked by the model on its own:

```
git clone https://github.com/mattpocock/skills ~/dev/mattpocock
scripts/hide-plugin-skills.sh
claude plugin marketplace add ~/.claude/local-marketplaces/mattpocock
claude plugin install mattpocock-skills@mattpocock
```

Hidden is the only safe state for it. The plugin installs all of his skills, so
`mattpocock-skills:grilling`, `:domain-modeling`, `:to-tickets`, and
`:improve-codebase-architecture` sit beside their `kit:` forks — the overlap
`adopt-skill.sh` exists to remove, and it cannot remove one skill from inside a
plugin. `skillOverrides` does not reach plugin skills, so the script sets
`disable-model-invocation: true` in each `SKILL.md` instead.

It sets it in a second clone, never in `~/dev/mattpocock`. That checkout is the
default `SKILLS_REPO` that `adopt-skill.sh` copies from and the one his forks'
sidecars name for `check-upstream.sh`; patched frontmatter there would ride
into every fork. A
directory marketplace is read in place, so the clone is the live install — to
take upstream changes, pull `~/dev/mattpocock` and re-run the script, which
discards its own edits, fast-forwards the clone, and hides again. A new session
picks it up; there is no `claude plugin update` step.

The [`skills`][skills-cli] CLI (`npx skills add mattpocock/skills`) installs
loose, un-namespaced copies into `~/.agents/skills` instead. `skillOverrides`
can hide those, but they are fetched from GitHub and go stale against the
checkout the fork review reads.

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
[humanlayer]: https://github.com/humanlayer/skills
[skills-cli]: https://github.com/vercel-labs/skills
