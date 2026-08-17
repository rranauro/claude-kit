# claude-kit

A ticket-to-merge workflow for [Claude Code](https://claude.com/claude-code),
packaged as a plugin. It covers the path from "we should probably do something
about X" to a merged PR and a cleaned-up worktree, with the design vocabulary
that keeps the work honest along the way.

## Install

```
/plugin marketplace add rranauro/claude-kit
/plugin install kit@claude-kit
```

Everything is namespaced under `kit:`. You need **GitHub** (via `gh`) and **git
worktrees**; there's nothing to configure and no vocabulary to adopt.

## The loop

```
/kit:architect     talk about the problem, file lean issues
/kit:design        settle the approach, grill it, write the plan
/kit:start-ticket  isolated worktree, wired up, plan in hand
/kit:ship-ticket   TDD → simplify → PR → review → auto-merge → cleanup
```

Work that arrives rather than work you started enters at `/kit:triage`, which
grills the ticket's scope before an approach exists and then hands off to
`/kit:design`.

Two things run without you. `/kit:tend-prs` makes one stateless pass over every
open PR you own — triage the review round, push the fixes, enable auto-merge,
remove merged worktrees — so it runs headless on a launchd schedule. And a
`PostToolUse` hook fires a second independent reviewer the moment a PR opens.

That's the shape. There are ~15 commands and 5 skills in all; the full list is in
[docs/commands.md](docs/commands.md).

## Documentation

| | |
|---|---|
| [Commands and skills](docs/commands.md) | Every command, what it does, and what the kit assumes about your stack |
| [Why I built this](docs/why.md) | The reasoning behind the design commands, the review loop, and what orchestration adds over technique |
| [Worktrees](docs/worktrees.md) | The default layout, and how to delegate to your project's own worktree recipe |
| [Hooks](docs/hooks.md) | The PR-review and Rails-gate hooks, and how to register them per project |
| [The reviewer script](docs/pr-review.md) | One shared review prompt behind three entry points |
| [Scheduled tending](docs/scheduled-tending.md) | Running `/kit:tend-prs` unattended: install, permission grant, `kit-hold`, logs |
| [Companion skills](docs/companion-skills.md) | The mattpocock/skills the design commands call by name |

## License

MIT — see [LICENSE](LICENSE).
