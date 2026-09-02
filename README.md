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
/kit:design        settle the approach, grill it, store the plan on the issue
/kit:ship-ticket   TDD → simplify → PR, with gates you answer
                   … unattended, and it parks what it can't decide
```

It builds on the `kit:ticket-loop` skill, which is the one place the sequence
lives, and on `kit:start-ticket` under that, which wires the worktree and checks
that a plan actually exists before anything writes a line.

Work that arrives rather than work you started enters at `/kit:triage`, which
grills the ticket's scope before an approach exists and then hands off to
`/kit:design`.

The PR opens with auto-merge off and nothing left running on your machine.
Copilot reviews it, and a CI gate in the consuming project calls
`/kit:review-copilot` to triage the findings, push the fixes, and merge — see
[tending on a CI runner](docs/tending-on-a-runner.md).

That's the shape. There are ~13 commands and 11 skills in all; the full list is in
[docs/commands.md](docs/commands.md).

## Documentation

| | |
|---|---|
| [Commands and skills](docs/commands.md) | Every command, what it does, and what the kit assumes about your stack |
| [Why I built this](docs/why.md) | The reasoning behind the design commands, the review loop, and what orchestration adds over technique |
| [Worktrees](docs/worktrees.md) | The default layout, and how to delegate to your project's own worktree recipe |
| [Hooks](docs/hooks.md) | The Rails-gate hook, and how to register it per project |
| [The reviewer script](docs/pr-review.md) | One shared review prompt behind two entry points |
| [Tending on a CI runner](docs/tending-on-a-runner.md) | What happens to a PR after it opens: which command CI calls, the credential every act needs, and the trigger that never fires |
| [Companion skills](docs/companion-skills.md) | The mattpocock/skills the design commands call by name |

## License

MIT — see [LICENSE](LICENSE).
