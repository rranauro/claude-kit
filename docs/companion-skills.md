# Companion skills

I found [Matt Pocock's suite][pocock] about seven months after building this, and
took the nuggets that fit. The design commands call his skills by name at two
points, and carry a fork of a third:

| Called by | Skill | What it supplies |
|---|---|---|
| `/kit:architect` | `improve-codebase-architecture` | Offered instead of ad-hoc file reading when the topic is "this area feels wrong" rather than a specific question. |
| `/kit:design` step 2 | `codebase-design` | The deep-module vocabulary — interface, seam, depth, leverage — used as the axis for comparing approaches. |

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
`/kit:design` loses its comparison vocabulary and `/kit:architect` loses its
scan-first opening move. The adversarial pass is no longer at risk: it ships
with the plugin.

The two suites compose rather than compete. `codebase-design` asks how deep a
module should be; `kit:behavior-placement` here asks *whose* the behavior is. And go
read the rest of his suite regardless of whether you use this one —
`improve-codebase-architecture` earns its place well beyond the one call
`/kit:architect` makes to it.

[pocock]: https://github.com/mattpocock/skills
[skills-cli]: https://github.com/vercel-labs/skills
