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

Everything the plugin ships is namespaced under `kit:` — `/kit:ship-ticket`,
`/kit:commit`, and so on. Plugin namespacing is unconditional in Claude Code;
the prefix comes from the `name` field in `plugins/kit/.claude-plugin/plugin.json`.

## What's in it

### Commands

| Command | What it does |
|---|---|
| `/kit:architect` | The problem conversation. Explores an idea, questions the premise, looks at how others solve it — and files lean GitHub issues only if the conversation earns them. |
| `/kit:design` | The *how*, once the *what* is settled. Places the behavior, compares approaches, grills the choice, and writes the durable plan. |
| `/kit:start-ticket` | Reads an issue, creates an isolated git worktree off `origin/main` — or delegates to your project's own worktree command — wires up gitignored runtime files, and picks up any plan `/kit:design` left behind. |
| `/kit:ship-ticket` | Orchestrates the rest: TDD, a simplify pass, PR, automated review, auto-merge, cleanup. |
| `/kit:tend-prs` | The unattended half. One pass over every open PR you own: triage the review round that landed, push the fixes, enable auto-merge, and remove the worktrees whose PRs have merged. Stateless, so `/loop 20m /kit:tend-prs` is the whole setup. Skips anything you're working in. |
| `/kit:polish-ticket` | Runs a catch-all polish ticket. The user reports problems one at a time; each is triaged into an inline fix on the branch or its own filed ticket. |
| `/kit:walkthrough` | Verifies a branch in-app one step at a time, against a checklist derived from the issue's acceptance criteria and the diff. The position lives in a file, so a bug found mid-walk detours into triage and returns to the same step. |
| `/kit:commit` | Focused commit with a real message. Reads the project's test, lint, and security gates from `CLAUDE.md`/manifest/CI and runs them on what changed. |
| `/kit:new-pull-request` | Opens a PR with a closing keyword wired to the issue. |
| `/kit:review-copilot` | Takes automated review findings one at a time and verifies each against the code before acting, recording the reasoning for every one in the commit body. |
| `/kit:start-review` | The other side of the workflow: a PR arrives and you have to judge it. Checks the branch out in its own worktree, runs the headless reviewer, and walks the app. Assess-only on a colleague's PR; a fix loop on your own. |
| `/kit:cleanup-worktree` | Removes a merged worktree and its branch. |
| `/kit:worktree-gc` | The periodic pass for the ones that never went through `/kit:cleanup-worktree`. Re-checks merge state against a fresh `origin/main`, and sweeps the untracked husks `git worktree remove` leaves behind. |

### Skills

| Skill | What it does |
|---|---|
| `kit:behavior-placement` | Where behavior belongs — model, value object, or service — and whether the app already derives the answer. |
| `kit:to-tickets` | Cuts an epic into tracer-bullet tickets, each declaring which tickets must merge before it can start. Adopted from mattpocock/skills; the local fork adds a machine-readable edge marker so `/kit:tend-prs` can start them unattended, and an out-of-scope section so each ticket stands as its own brief. |
| `kit:writing-tickets` | Lean issues that state the problem and the decision without freezing an implementation. |
| `kit:worktree-conventions` | Where worktrees live and who creates them — delegates to the project's own command when it has one, and detects the resulting path from git rather than assuming it. |

### Worktree layout

By default worktrees go under `.claude/worktrees/<branch>` inside the repo, and
`/kit:start-ticket` links the gitignored files the app needs to boot.

If your project already owns this — a `just` recipe, a `make` target, a setup
script that creates the worktree *and* installs deps and links a dev proxy —
declare it in `CLAUDE.md` and the commands delegate instead:

```markdown
## Worktrees
- create: `just worktree <branch>`
- remove: `just del-worktree <branch>`
- provisions: yes
```

`provisions: yes` means `/kit:start-ticket` skips its own wiring rather than
symlinking on top of a real install. The path is never configured — it's read
back from `git worktree list --porcelain` after your command runs, so a layout
this suite has never seen still works.

Declaring `remove` matters more than it looks. A recipe that unlinks a dev proxy
or drops a registered subdomain is doing something no generic
`git worktree remove` can reconstruct, and skipping it leaks that resource on
every cleanup.

It also narrows what `/kit:worktree-gc` will delete. Under the built-in layout the
directory holds nothing but worktrees, so anything git no longer names is
garbage. Under a sibling layout like `../<repo>-<branch>`, the same diff would
propose deleting unrelated repositories that happen to share the parent — so gc
falls back to sweeping only paths it removed in that run, and says so.

### Hooks

Both live in `plugins/kit/hooks/`. Register them in a **project's**
`.claude/settings.json` rather than the global one, so each fires only for the
repos you want it in.

`pr-review-on-create.sh` — a `PostToolUse` hook that fires when `gh pr create`
succeeds and delegates to `scripts/pr-review.sh`, which runs the review headless
and posts it as a comment. Kill switch: `export SKIP_PR_REVIEW=1`.

`rails-quality-gates.sh` — a `PreToolUse` hook that holds `git commit` to RuboCop
and Brakeman on the staged Ruby files, blocking the commit with the tool output
so Claude fixes it and retries. No-ops unless the `Gemfile` carries both. Kill
switch: `export SKIP_RAILS_GATES=1`.

**Registering them.** Add to the project's `.claude/settings.json` — both match
on `Bash`, and they differ only in the event they hang off:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /ABSOLUTE/PATH/TO/claude-kit/plugins/kit/hooks/pr-review-on-create.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /ABSOLUTE/PATH/TO/claude-kit/plugins/kit/hooks/rails-quality-gates.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

Use an absolute path. `${CLAUDE_PLUGIN_ROOT}` only resolves for hooks a plugin
registers itself, not for ones you wire up in your own settings — if you
installed via the marketplace, the scripts are under
`~/.claude/plugins/marketplaces/claude-kit/plugins/kit/hooks/`.

The `timeout` on the Rails gate is worth keeping: Brakeman scans the whole app
and the default timeout is not generous enough for a large one. Each script
filters its own trigger — `pr-review-on-create` acts only on `gh pr create`,
`rails-quality-gates` only on `git commit` — so the broad `Bash` matcher costs a
fast no-op on every other command.

**These are deliberately not auto-registered.** A plugin can ship a
`hooks/hooks.json` that turns its hooks on for every repo the plugin is enabled
in. Neither of these should work that way: one spends tokens on a headless
review, the other blocks your commits. Opting in per project is the point.

**Why the Rails opinion is a hook and not a command.** A gate is binary — did it
pass? — and a hook can't be talked out of it the way a command can when the code
looks fine. Remediation is the opposite: triaging a Brakeman finding into a real
XSS or a false positive is judgment, and a shell script has none. So the hook
enforces and `/kit:commit` fixes, which keeps `/kit:commit` stack-neutral and lets
non-Rails users simply not register the hook. Tests stay in the command for the
same reason — choosing which tests cover a change is judgment, and a full suite
would blow the hook timeout.

### The reviewer script

`plugins/kit/scripts/pr-review.sh` holds the review prompt, and
three entry points share it: the hook above, `/kit:start-review`, and a manual
re-run after you push fixes. Keeping one copy is what makes a second pass
comparable to the first.

It decides delivery by authorship. Your own PR gets the review posted as a
comment; a colleague's gets a file under `<main-checkout>/reviews/pr-<n>/`, and
posting to it requires an explicit `--post`. An unresolved login falls to the
file side — the failure mode should be a review you have to go read, not an
uninvited comment on someone else's work. Scope narrows the same way: full
categories on your own PRs, bugs and security only on everyone else's.

Everything is detected at runtime — repo via `gh`, your login via `gh api user`,
the main checkout via `git rev-parse --git-common-dir` so artifacts survive the
worktree they were produced in. There is no config file to write. Run it by hand
with `pr-review.sh --help`.

## Why I built this

**Better designs, not faster typing.** `/kit:architect` and `/kit:design` are the
foundation — an argument with the model about the problem, and then about the
shape of the answer, before any code exists. What comes out is a design that's
easier to debug and needs less hand-holding, which is what makes it reasonable to
hand the coding to the model.

They're deliberately separate. A conversation that has somewhere to be stops
being a conversation: if every session ends in tickets, the model starts
narrowing options in turn two so a decision can be reached. `/kit:architect` is
allowed to end unresolved. `/kit:design` is where rigor is unconditional, and you
only enter it once you know what you're building.

**Reviewing became the bottleneck.** Once construction got cheap, review was what
ate my time. GitHub is the substrate here, so the workflow automates that phase
where it can: the `pr-review-on-create` hook fires a review the moment a PR opens,
and `/kit:tend-prs` triages what comes back — on a loop, with nobody watching.

**Two models see different things.** Running more than one reviewer over the same
diff turns up bugs and inconsistencies uncannily well, and it happens before any
human reviewer engages. They stop requesting changes for things a bot would have
caught, and spend their attention on in-app testing instead.

## What the orchestration adds

Techniques are the easy part. Everything between them is where the workflow lives:

- **Sequence and gates.** `/kit:ship-ticket` is an orchestrator, not a technique. It
  knows the simplify pass runs *before* the PR exists, that auto-merge stays off
  until the first review round is answered, and that pushing waits for you. The
  ordering is the content — it's what stops you skipping the uncomfortable step
  because the code looks fine.
- **Handoff across a context boundary.** `/kit:architect` writes a plan into a
  gitignored `plans/` store that `/kit:start-ticket` symlinks into every worktree, so
  the intended move is to converge, drop the plan, clear context, and run
  `/kit:start-ticket` on it immediately — a clean window to implement in, against the
  repo the plan was written for. The store crosses that boundary rather than
  banking decisions: `/kit:start-ticket` asks whether the plan is still fresh and, when
  it isn't, verifies the plan's anchors against the repo before proceeding. A plan
  that sat a week is a prescription written against code that has moved — the same
  argument that keeps solutions out of tickets.
- **Worktree plumbing.** `git worktree add` gives you a checkout missing every
  gitignored file the app needs to boot. `/kit:start-ticket` wires those back up, and
  enforces one worktree per issue — two is a trap that hides your own changes.
- **Nothing to adopt.** No label vocabulary, no triage states, no `docs/agents/`
  config, no block written into your `CLAUDE.md`. These commands read issues and
  open PRs; how you triage, label, and run your process stays yours.
- **A review loop that distrusts reviewers.** `/kit:review-copilot` merges findings
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

**Tickets should state the problem, not the solution.** `kit:writing-tickets` pushes
the outcome into vocabulary the app already has — not "output `data-field` names
are a superset of the input's," which sends someone off to write a parser, but
"the redesigned component must still declare every field the original declared,"
which sends them to the schema.

**Behavior decisions belong with the human, not the model.** Model, value object,
or service is a structural call you live with, so `kit:behavior-placement` hands you
the priority order and the smells that mean you got it wrong — the loudest being
a `Service.call(model:, …)` whose body mostly reads from `model`.

**Converging isn't the same as being right.** A design conversation converges on
whatever it drifted toward. `/kit:design` ends with an adversarial pass over the
agreed direction before the plan gets written, on the theory that the decision
nobody argued about is the one most likely to be wrong.

## Assumptions

These commands assume **GitHub** (via `gh`) and **git worktrees**. `/kit:ship-ticket`
additionally assumes a test suite it can run per-file.

**On stacks.** The workflow was developed on Rails, but the commands are the
generic path and I keep it honest: `/kit:commit` reads your test, lint, and security
commands from `CLAUDE.md`, the manifest, or CI rather than assuming them, and
`/kit:ship-ticket` Phase 4 uses your project's test framework with the RSpec form
shown as a worked example. The Rails opinions live in a hook you opt into, not in
the commands. What's left is labeled — the encrypted-credentials wiring in
`/kit:start-ticket` is marked as an example to adapt. If you hit an assumption that
isn't marked, that's a bug.

`/kit:start-ticket` resolves paths with `git rev-parse --show-toplevel`, so there's
nothing machine-specific to edit before use.

**External commands these call.** Beyond the companion skills below, the
workflow invokes `/simplify` (`/kit:ship-ticket` Phase 4b), `/loop` (drives
`/kit:tend-prs`), and optionally `/target-debug` (reads the `tickets/` notes
`/kit:new-pull-request` writes). Each degrades to a skipped step if you don't have
it, rather than failing.

## Companion skills

I found [Matt Pocock's suite][pocock] about seven months after building this, and
took the nuggets that fit. The design commands call his skills by name at three
points:

| Called by | Skill | What it supplies |
|---|---|---|
| `/kit:architect` | `improve-codebase-architecture` | Offered instead of ad-hoc file reading when the topic is "this area feels wrong" rather than a specific question. |
| `/kit:design` step 2 | `codebase-design` | The deep-module vocabulary — interface, seam, depth, leverage — used as the axis for comparing approaches. |
| `/kit:design` step 4 | `grilling` | The adversarial pass over the converged direction, before the plan is written. |

Install them with the [`skills`][skills-cli] CLI:

```
npx skills add mattpocock/skills
```

Claude Code reads global skills from `~/.claude/skills`; the CLI's universal
target is `~/.agents/skills`. If you install for a non-Claude agent, symlink one
to the other so Claude Code sees them.

These are referenced, not bundled. Without them the commands still run —
`/kit:design` loses its comparison vocabulary and its adversarial pass, and
`/kit:architect` loses its scan-first opening move.

The two suites compose rather than compete. `codebase-design` asks how deep a
module should be; `kit:behavior-placement` here asks *whose* the behavior is. And go
read the rest of his suite regardless of whether you use this one —
`improve-codebase-architecture` earns its place well beyond the one call
`/kit:architect` makes to it.

[pocock]: https://github.com/mattpocock/skills
[skills-cli]: https://github.com/vercel-labs/skills

## License

MIT — see [LICENSE](LICENSE).
