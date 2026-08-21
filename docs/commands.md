# Commands and skills

Everything the plugin ships is namespaced under `kit:` — `/kit:ship-ticket`,
`/kit:commit`, and so on. Plugin namespacing is unconditional in Claude Code;
the prefix comes from the `name` field in `plugins/kit/.claude-plugin/plugin.json`.

## Commands

### Deciding what to build

| Command | What it does |
|---|---|
| `/kit:architect` | The problem conversation. Explores an idea, questions the premise, looks at how others solve it — and files lean GitHub issues only if the conversation earns them. |
| `/kit:design` | The *how*, once the *what* is settled. Places the behavior, compares approaches, grills the choice, and writes the durable plan. |
| `/kit:triage` | The lane for work that arrived rather than work you started. Bins an issue (fixed, duplicate, parked, not-a-ticket), grills its *scope* before any approach exists — which adjacent decisions fold in now, and which are their own tickets — then runs `/kit:design` and leaves the brief on the issue, where an agent that never had your `plans/` directory can read it. |

### Building it

| Command | What it does |
|---|---|
| `/kit:start-ticket` | Reads an issue, creates an isolated git worktree off `origin/main` — or delegates to your project's own worktree command — wires up gitignored runtime files, and picks up any plan `/kit:design` left behind. |
| `/kit:ship-ticket` | Orchestrates the rest: TDD, a simplify pass, PR, automated review, auto-merge, cleanup. |
| `/kit:start-next` | Picks up the next epic ticket whose blocking edges have all closed — lowest issue number first — and hands it to `/kit:ship-ticket`. Deliberate by design: `/kit:tend-prs` runs unattended because it never writes an implementation, and this is the step that does. |
| `/kit:polish-ticket` | Runs a catch-all polish ticket. The user reports problems one at a time; each is triaged into an inline fix on the branch or its own filed ticket. |
| `/kit:commit` | Focused commit with a real message. Reads the project's test, lint, and security gates from `CLAUDE.md`/manifest/CI and runs them on what changed. |
| `/kit:new-pull-request` | Opens a PR with a closing keyword wired to the issue. |
| `/kit:pin-it` | Parks a requirement that surfaced mid-debug but isn't ready to be discussed — culled to what's expensive to re-derive, saved outside version control at the main checkout so it survives the worktree it was written in. `list` shows what's pinned and flags what's gone stale; a slug brings one back and triages it into an issue, a fix, or a drop. |

### Reviewing and merging

| Command | What it does |
|---|---|
| `/kit:tend-prs` | The unattended half. One pass over every open PR you own: triage the review round that landed, push the fixes, enable auto-merge, and remove the worktrees whose PRs have merged. Stateless and cold-start safe, so it runs headless on a launchd schedule — see [scheduled tending](scheduled-tending.md). Skips anything you're working in. Reports outstanding `/kit:pin-it` pins so the unread ones surface on their own. |
| `/kit:review-copilot` | Takes automated review findings one at a time and verifies each against the code before acting, recording the reasoning for every one in the commit body. |
| `/kit:start-review` | The other side of the workflow: a PR arrives and you have to judge it. Checks the branch out in its own worktree, runs the headless reviewer, and walks the app. Assess-only on a colleague's PR; a fix loop on your own. |
| `/kit:walkthrough` | Verifies a branch in-app one step at a time, against a checklist derived from the issue's acceptance criteria and the diff. The position lives in a file, so a bug found mid-walk detours into triage and returns to the same step. |

### Housekeeping

| Command | What it does |
|---|---|
| `/kit:cleanup-worktree` | Removes a merged worktree and its branch. |
| `/kit:worktree-gc` | The periodic pass for the ones that never went through `/kit:cleanup-worktree`. Re-checks merge state against a fresh `origin/main`, and sweeps the untracked husks `git worktree remove` leaves behind. |
| `/kit:triage-memory` | The same pass for auto-memory. Bins every memory as stale, workflow, duplicate, or unclassified, then clears it down — moving what's worth keeping into an on-demand `WORKFLOW.md` and archiving before deleting. `--dry-run` reports what you'd get back and what you'd lose, without writing anything. |

## Skills

| Skill | What it does |
|---|---|
| `kit:behavior-placement` | Where behavior belongs — model, value object, or service — and whether the app already derives the answer. |
| `kit:grilling` | The adversarial pass over a converged direction or a ticket's boundary, run as rounds of numbered questions. Adopted from mattpocock/skills; the local fork fences the grilling to what the change actually builds, so the frontier holds only questions whose answers change this implementation, parks everything adjacent instead of asking about it, and stops when no open question can move the code rather than when the design tree is exhausted. |
| `kit:to-tickets` | Cuts an epic into tracer-bullet tickets, each declaring which tickets must merge before it can start. Adopted from mattpocock/skills; the local fork adds a machine-readable edge marker so `/kit:start-next` can pick them up on its own, and an out-of-scope section so each ticket stands as its own brief. |
| `kit:writing-tickets` | Lean issues that state the problem and the decision without freezing an implementation. |
| `kit:worktree-conventions` | Where worktrees live and who creates them — delegates to the project's own command when it has one, and detects the resulting path from git rather than assuming it. See [worktrees](worktrees.md). |
| `kit:triage-memory` | Clears down an auto-memory directory that has grown past its usefulness — bins every memory as stale, workflow, duplicate, or unclassified, and trades continuously-loaded memory for a `WORKFLOW.md` that's read only when the work calls for it. |

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

**External commands these call.** Beyond the [companion skills](companion-skills.md),
the workflow invokes `/simplify` (`/kit:ship-ticket` Phase 4b), `/loop` (drives
`/kit:tend-prs`), and optionally `/target-debug` (reads the `tickets/` notes
`/kit:new-pull-request` writes). Each degrades to a skipped step if you don't have
it, rather than failing.
