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
| `/commit` | Focused commit with a real message. Reads the project's test, lint, and security gates from `CLAUDE.md`/manifest/CI and runs them on what changed. |
| `/new-pull-request` | Opens a PR with a closing keyword wired to the issue. |
| `/review-copilot` | Takes automated review findings one at a time and verifies each against the code before acting, recording the reasoning for every one in the commit body. |
| `/wait-copilot` | Polls a PR until the automated reviewers post. |
| `/cleanup-worktree` | Removes a merged worktree and its branch. |

### Skills

| Skill | What it does |
|---|---|
| `behavior-placement` | Where behavior belongs — model, value object, or service — and whether the app already derives the answer. |
| `writing-tickets` | Lean issues that state the problem and the decision without freezing an implementation. |

### Hooks

Both live in `plugins/ticket-workflow/hooks/`. Register them in a **project's**
`.claude/settings.json` rather than the global one, so each fires only for the
repos you want it in.

`pr-review-on-create.sh` — a `PostToolUse` hook that fires when `gh pr create`
succeeds and spawns a detached `claude -p` to review the PR and post the review
as a comment. Kill switch: `export SKIP_PR_REVIEW=1`.

`rails-quality-gates.sh` — a `PreToolUse` hook that holds `git commit` to RuboCop
and Brakeman on the staged Ruby files, blocking the commit with the tool output
so Claude fixes it and retries. No-ops unless the `Gemfile` carries both. Kill
switch: `export SKIP_RAILS_GATES=1`.

**Why the Rails opinion is a hook and not a command.** A gate is binary — did it
pass? — and a hook can't be talked out of it the way a command can when the code
looks fine. Remediation is the opposite: triaging a Brakeman finding into a real
XSS or a false positive is judgment, and a shell script has none. So the hook
enforces and `/commit` fixes, which keeps `/commit` stack-neutral and lets
non-Rails users simply not register the hook. Tests stay in the command for the
same reason — choosing which tests cover a change is judgment, and a full suite
would blow the hook timeout.

## Why I built this

**Better designs, not faster typing.** `/architect` is the foundation. It's an
argument with the model about the problem before any code exists, and what comes
out is a design that's easier to debug and needs less hand-holding — which is
what makes it reasonable to hand the coding to the model.

**Reviewing became the bottleneck.** Once construction got cheap, review was what
ate my time. GitHub is the substrate here, so the workflow automates that phase
where it can: `/new-pull-request` and `/wait-copilot` drive `gh`, and the
`pr-review-on-create` hook fires a review the moment a PR opens.

**Two models see different things.** Running more than one reviewer over the same
diff turns up bugs and inconsistencies uncannily well, and it happens before any
human reviewer engages. They stop requesting changes for things a bot would have
caught, and spend their attention on in-app testing instead.

## What the orchestration adds

Techniques are the easy part. Everything between them is where the workflow lives:

- **Sequence and gates.** `/ship-ticket` is an orchestrator, not a technique. It
  knows the simplify pass runs *before* the PR exists, that auto-merge stays off
  until the first review round is answered, and that pushing waits for you. The
  ordering is the content — it's what stops you skipping the uncomfortable step
  because the code looks fine.
- **Handoff across a context boundary.** `/architect` writes a plan into a
  gitignored `plans/` store that `/start-ticket` symlinks into every worktree, so
  the intended move is to converge, drop the plan, clear context, and run
  `/start-ticket` on it immediately — a clean window to implement in, against the
  repo the plan was written for. The store crosses that boundary rather than
  banking decisions: `/start-ticket` asks whether the plan is still fresh and, when
  it isn't, verifies the plan's anchors against the repo before proceeding. A plan
  that sat a week is a prescription written against code that has moved — the same
  argument that keeps solutions out of tickets.
- **Worktree plumbing.** `git worktree add` gives you a checkout missing every
  gitignored file the app needs to boot. `/start-ticket` wires those back up, and
  enforces one worktree per issue — two is a trap that hides your own changes.
- **Nothing to adopt.** No label vocabulary, no triage states, no `docs/agents/`
  config, no block written into your `CLAUDE.md`. These commands read issues and
  open PRs; how you triage, label, and run your process stays yours.
- **A review loop that distrusts reviewers.** `/review-copilot` merges findings
  from multiple bots into one bucket per line and checks each claim against the
  actual code before acting on it — a "missing nil check" on a provably non-nil
  path gets classified and dropped, not applied. Every decision, including the
  rejections, lands in the commit body so the reasoning is durable in git rather
  than lost in a chat log. The second reviewer is coverage, not redundancy — and
  when two land on the same line independently, that corroboration is the
  strongest signal you get. Still a signal to verify, not a verdict: agreement
  makes a finding more likely to be real, never certain.

## The ideas behind it

Three opinions do most of the work here.

**Tickets should state the problem, not the solution.** `writing-tickets` pushes
the outcome into vocabulary the app already has — not "output `data-field` names
are a superset of the input's," which sends someone off to write a parser, but
"the redesigned component must still declare every field the original declared,"
which sends them to the schema.

**Behavior decisions belong with the human, not the model.** Model, value object,
or service is a structural call you live with, so `behavior-placement` hands you
the priority order and the smells that mean you got it wrong — the loudest being
a `Service.call(model:, …)` whose body mostly reads from `model`.

**Converging isn't the same as being right.** A design conversation converges on
whatever it drifted toward. `/architect` ends with an adversarial pass over the
agreed direction before any ticket gets written, on the theory that the decision
nobody argued about is the one most likely to be wrong.

## Assumptions

These commands assume **GitHub** (via `gh`) and **git worktrees**. `/ship-ticket`
additionally assumes a test suite it can run per-file.

**On stacks.** The workflow was developed on Rails, but the commands are the
generic path and I keep it honest: `/commit` reads your test, lint, and security
commands from `CLAUDE.md`, the manifest, or CI rather than assuming them, and
`/ship-ticket` Phase 4 uses your project's test framework with the RSpec form
shown as a worked example. The Rails opinions live in a hook you opt into, not in
the commands. What's left is labeled — the encrypted-credentials wiring in
`/start-ticket` is marked as an example to adapt. If you hit an assumption that
isn't marked, that's a bug.

`/start-ticket` resolves paths with `git rev-parse --show-toplevel`, so there's
nothing machine-specific to edit before use.

**External commands these call.** Beyond the companion skills below, the
workflow invokes `/simplify` (`/ship-ticket` Phase 4b), `/loop` (`/wait-copilot`
polling), and optionally `/target-debug` (reads the `tickets/` notes
`/new-pull-request` writes). Each degrades to a skipped step if you don't have
it, rather than failing.

## Companion skills

I found [Matt Pocock's suite][pocock] about seven months after building this, and
took the nuggets that fit. `/architect` calls his skills by name at three points:

| Called by | Skill | What it supplies |
|---|---|---|
| `/architect` Phase 1 | `improve-codebase-architecture` | Offered instead of ad-hoc file reading when the topic is "this area feels wrong" rather than a specific change; its scan feeds Phase 2. |
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
`/architect` loses its comparison vocabulary, its adversarial pass, and its
scan-first opening move.

The two suites compose rather than compete. `codebase-design` asks how deep a
module should be; `behavior-placement` here asks *whose* the behavior is. And go
read the rest of his suite regardless of whether you use this one —
`improve-codebase-architecture` earns its place well beyond the one call
`/architect` makes to it.

[pocock]: https://github.com/mattpocock/skills
[skills-cli]: https://github.com/vercel-labs/skills

## License

MIT — see [LICENSE](LICENSE).
