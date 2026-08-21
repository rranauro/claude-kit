# Companion skills

I found [Matt Pocock's suite][pocock] about seven months after building this, and
took the nuggets that fit. The design commands call one of his skills by name,
and carry a fork of a second:

| Called by | Skill | What it supplies |
|---|---|---|
| `/kit:architect` | `improve-codebase-architecture` | Offered instead of ad-hoc file reading when the topic is "this area feels wrong" rather than a specific question. |

`grilling` used to be the third. It is now forked into the plugin as
`kit:grilling` — see [commands](commands.md) for what the fork changes and
`plugins/kit/skills/grilling/UPSTREAM` for the sha it was taken at. The upstream
copy stays installable and untouched; the commands name the fork explicitly so
the two never get confused for each other.

Install them with the [`skills`][skills-cli] CLI:

```
npx skills add mattpocock/skills
```

Claude Code reads global skills from `~/.claude/skills`; the CLI's universal
target is `~/.agents/skills`. If you install for a non-Claude agent, symlink one
to the other so Claude Code sees them.

These are referenced, not bundled. Without them the commands still run —
`/kit:architect` loses its scan-first opening move. The adversarial pass and the
comparison vocabulary are no longer at risk: both ship with the plugin.

`codebase-design` used to be the second call. `/kit:design` now uses
`kit:rails-codebase-design` instead, written here rather than adopted. The
upstream skill is deliberately scale-agnostic — a "module" is a function, a
class, or a tier-spanning slice — and its testability advice is written for
functional code. Against an in-process Rails object that combination produced
false findings and no way to conclude a class was already fine, which left the
adversarial pass with nothing to check. The replacement trades portability for
counts that either fire or don't, and an explicit list of what is not a finding.

The two suites still compose rather than compete. `kit:rails-codebase-design`
asks what shape an object should take; `kit:behavior-placement` asks *whose* the
behavior is. And go
read the rest of his suite regardless of whether you use this one —
`improve-codebase-architecture` earns its place well beyond the one call
`/kit:architect` makes to it.

[pocock]: https://github.com/mattpocock/skills
[skills-cli]: https://github.com/vercel-labs/skills
