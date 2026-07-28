# claude-kit

A ticket-to-merge workflow for [Claude Code](https://claude.com/claude-code),
packaged as a plugin. It covers the path from "we should probably do something
about X" to a merged PR and a cleaned-up worktree, with the design vocabulary
that keeps the work honest along the way.

## Install

```
/plugin marketplace add rranauro/claude-kit
/plugin install ticket-workflow@claude-kit
```

## What's in it

### Commands

| Command | What it does |
|---|---|
| `/architect` | The design conversation. Explores the problem, weighs approaches, converges, then files lean GitHub issues. |
| `/start-ticket` | Reads an issue, creates an isolated git worktree off `origin/main`, wires up gitignored runtime files, and picks up any plan `/architect` left behind. |
| `/ship-ticket` | Orchestrates the rest: TDD, a simplify pass, PR, automated review, auto-merge, cleanup. |
| `/commit` | Focused commit with a real message. |
| `/new-pull-request` | Opens a PR with a closing keyword wired to the issue. |
| `/review-copilot` | Walks automated review findings one at a time, verifying each against the code before accepting it. |
| `/wait-copilot` | Polls a PR until the automated reviewers post. |
| `/cleanup-worktree` | Removes a merged worktree and its branch. |

### Skills

| Skill | What it does |
|---|---|
| `behavior-placement` | Where behavior belongs — model, value object, or service — and whether the app already derives the answer. |
| `writing-tickets` | Lean issues that state the problem and the decision without freezing an implementation. |

### Hooks

`hooks/pr-review-on-create.sh` — a `PostToolUse` hook that fires when
`gh pr create` succeeds and spawns a detached `claude -p` to review the PR and
post the review as a comment. Register it in a **project's**
`.claude/settings.json` rather than the global one, so it only runs for repos
you want reviewed. Kill switch: `export SKIP_PR_REVIEW=1`.

## The ideas behind it

Three opinions do most of the work here.

**Tickets should state the problem, not the solution.** A ticket that freezes a
file list or a class shape reaches the implementer with authority it never
earned — those details were guesses made without the code open, and they rot as
the repo drifts. `writing-tickets` pushes outcomes into domain vocabulary
instead: not "output `data-field` names are a superset of the input's" (which
sends someone off to write a parser) but "the redesigned component must still
declare every field the original declared" (which sends them to the schema the
app already has).

**Behavior belongs to whoever owns the data.** Services are the residual, not
the default. `behavior-placement` gives the priority order — model, then value
object, then service — and the smells that mean you got it wrong, the loudest
being a `Service.call(model:, …)` whose body mostly reads from `model`.

**Converging isn't the same as being right.** A design conversation converges on
whatever it drifted toward. `/architect` ends with an adversarial pass over the
agreed direction before any ticket gets written, on the theory that the decision
nobody argued about is the one most likely to be wrong.

## Assumptions

These commands assume **GitHub** (via `gh`) and **git worktrees**. `/ship-ticket`
additionally assumes a test suite it can run per-file. Nothing assumes a
particular language — the one Rails-flavored example, encrypted credentials in
`/start-ticket`, is marked as an example to adapt.

`/start-ticket` resolves paths with `git rev-parse --show-toplevel`, so there's
nothing machine-specific to edit before use.

## Pairs well with

These are not included — they're other people's work, and this repo ships only
its own. But the workflow was built alongside them and references them by name:

- Matt Pocock's skills suite, in particular `codebase-design` (the deep-module
  vocabulary `/architect` uses to compare approaches) and `grilling` (the
  adversarial pass at the end of Phase 3).

If you don't have them installed, the commands still work — they'll just skip
those steps.

## License

MIT — see [LICENSE](LICENSE).
