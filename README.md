# claude-kit

A ticket-to-merge workflow for [Claude Code](https://claude.com/claude-code),
packaged as a plugin. It covers the path from "we should probably do something
about X" to a merged PR and a cleaned-up worktree, with the design vocabulary
that keeps the work honest along the way.

## Why I built this

Claude has collapsed the cost of construction. Work that took months takes days,
and that moves the bottleneck: the scarce input is no longer how fast you can
build, it's whether what you're building should stand.

An architect can put up a building far faster now. The design still decides
whether it's worth having. And software rarely fails by falling over — it fails
by standing, and calcifying.

So the job has shifted. As developers we have to be architects, and own what the
building looks like. Every command here exists to force that ownership at the
moment it's cheapest: before the ticket is written, before the class is named,
before the PR is open.

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

## Why this and not just a pile of skills?

Good skills already exist for most of the individual moves here — including in
[Matt Pocock's suite][pocock], which has `to-tickets`, `implement`, `tdd`,
`code-review`, and `handoff`. If you want the techniques, take them from there.

What's missing when you have techniques but no assembly is everything between
them:

- **Sequence and gates.** `/ship-ticket` is an orchestrator, not a technique. It
  knows the simplify pass runs *before* the PR exists, that auto-merge stays off
  until the first review round is answered, and that pushing waits for you. The
  ordering is the content — it's what stops you skipping the uncomfortable step
  because the code looks fine.
- **Handoff that survives a new session.** `/architect` writes a plan into a
  gitignored `plans/` store that `/start-ticket` symlinks into every worktree, so
  a decision reached on Tuesday is still there on Friday from a fresh checkout.
- **Worktree plumbing.** `git worktree add` gives you a checkout missing every
  gitignored file the app needs to boot. `/start-ticket` wires those back up, and
  enforces one worktree per issue — two is a trap that hides your own changes.
- **Nothing to adopt.** No label vocabulary, no triage states, no `docs/agents/`
  config, no block written into your `CLAUDE.md`. These commands read issues and
  open PRs; how you triage, label, and run your process stays yours.
- **A review loop that distrusts reviewers.** `/review-copilot` merges findings
  from multiple bots into one bucket per line and makes you verify each claim
  against the code before accepting it. Two things make this worth the ceremony.
  Models aren't ranked better and worse so much as *different* — run two over the
  same diff and they surface strikingly different issues, so the second reviewer
  is coverage, not redundancy. And when they independently land on the same line,
  that corroboration is the strongest signal you get. It's still a signal to
  verify, not a verdict: agreement makes a finding more likely to be real, never
  certain.

The two skills here fill gaps rather than compete: `behavior-placement` asks
*whose* the behavior is, where `codebase-design` asks how deep a module should
be, and `writing-tickets` is about what a ticket must **not** freeze.

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

## Companion skills

Two commands here call skills from [Matt Pocock's suite][pocock] by name:

| Called by | Skill | What it supplies |
|---|---|---|
| `/architect` Phase 2 | `codebase-design` | The deep-module vocabulary — interface, seam, depth, leverage — used as the axis for comparing approaches. |
| `/architect` Phase 3 | `grilling` | The adversarial pass over the converged direction, before any ticket is written. |

Install them with the [`skills`][skills-cli] CLI:

```
npx skills add mattpocock/skills
```

Claude Code reads global skills from `~/.claude/skills`; the CLI's universal
target is `~/.agents/skills`. If you install for a non-Claude agent, symlink one
to the other so Claude Code sees them.

These are referenced, not bundled. Without them the commands still run —
`/architect` loses its comparison vocabulary and its adversarial pass.

[pocock]: https://github.com/mattpocock/skills
[skills-cli]: https://github.com/vercel-labs/skills

## License

MIT — see [LICENSE](LICENSE).
