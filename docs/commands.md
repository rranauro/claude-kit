# Commands and skills

Everything the plugin ships is namespaced under `kit:` — `/kit:ship-ticket`,
`/kit:commit`, and so on. Plugin namespacing is unconditional in Claude Code;
the prefix comes from the `name` field in `plugins/kit/.claude-plugin/plugin.json`.

## Commands

### Deciding what to build

| Command | What it does |
|---|---|
| `/kit:architect` | The problem conversation. Explores an idea, questions the premise, looks at how others solve it — and files lean GitHub issues only if the conversation earns them. |
| `/kit:design` | The *how*, once the *what* is settled. Places the behavior, compares approaches, grills the choice, and stores the plan on the issue it belongs to — where an agent that never had your `plans/` directory can read it. |
| `/kit:triage` | The lane for work that arrived rather than work you started. Bins an issue (fixed, duplicate, parked, not-a-ticket), grills its *scope* before any approach exists — which adjacent decisions fold in now, and which are their own tickets — then runs `/kit:design` and brings the body up to the bar an unattended agent can pick up from. |

### Building it

| Command | What it does |
|---|---|
| `/kit:start-ticket` | Reads an issue, creates an isolated git worktree off `origin/main` — or delegates to your project's own worktree command — wires up gitignored runtime files, and picks up any plan `/kit:design` left behind. |
| `/kit:ship-ticket` | Orchestrates the rest: TDD, a simplify pass, PR, automated review, auto-merge, cleanup. |
| `/kit:start-next` | Picks up the next epic ticket whose blocking edges have all closed — lowest issue number first — and hands it to `/kit:ship-ticket`. Skips any ticket carrying `kit-blocked`, the start-side twin of `kit-hold`: a ready ticket waiting on something no merge will clear, reported by name with its reason rather than silently withheld. Deliberate by design: `/kit:tend-prs` runs unattended because it never writes an implementation, and this is the step that does. |
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
| `/kit:triage-memory-run` | The same pass for auto-memory. Bins every memory as stale, workflow, duplicate, or unclassified, then clears it down — moving what's worth keeping into an on-demand `WORKFLOW.md` and archiving before deleting. `--dry-run` reports what you'd get back and what you'd lose, without writing anything. |

## Skills

| Skill | What it does |
|---|---|
| `kit:behavior-placement` | Where behavior belongs — model, value object, or service — and whether the app already derives the answer. |
| `kit:rails-codebase-design` | The axis `/kit:design` scores approaches on: the six properties of a well-shaped object, the counts that fire when one is missing, and an explicit list of what is *not* a finding — so a pass doesn't manufacture dependency-injection friction a Rails codebase never had. |
| `kit:improve-codebase-architecture` | The scan `/kit:architect` opens with when the topic is "this area feels wrong". Walks an area for the counts in `kit:rails-codebase-design`, discards everything on its not-a-finding list, and publishes an HTML report to `plans/` ranked strongest to weakest. Adopted from mattpocock/skills; the local fork swaps the module/interface/seam vocabulary for the Rails one, makes "name the caller it costs" a gate rather than a nicety, writes the report into the repo instead of `$TMPDIR` where it is unrecoverable, and **stops at the report** — exploring a candidate is an offer, not the next step. |
| `kit:domain-modeling` | Writing the project's glossary and its ADRs, at the three points where the model actually changes: a term argued in `/kit:architect`, a concept named or an alternative rejected in `/kit:design`, and the two artifacts a `kit:improve-codebase-architecture` scan leaves behind. Owns both formats: `CONTEXT-FORMAT` for a glossary entry, `ADR-FORMAT` for a decision. Adopted from mattpocock/skills; the local fork names where it's reached from and adds one gate upstream lacks — **an ADR must not restate a mechanism a doc already owns**, which is the way these directories actually rot. |
| `kit:grilling` | The confirmation pass over a converged direction or a ticket's boundary. Adopted from mattpocock/skills; the local fork diverges hard. It fences the pass to what the change actually builds and parks everything adjacent, and it **asserts rather than interrogates** — stating what it takes to be true with the evidence, so the user corrects rather than answers. A question is earned only where choosing differently changes performance, testability, or maintainability, and then it carries one alternative rather than a menu. An edge case that cannot name the input and the path reaching it is not raised at all. |
| `kit:to-tickets` | Cuts an epic into tracer-bullet tickets, each declaring which tickets must merge before it can start. Adopted from mattpocock/skills; the local fork adds a machine-readable edge marker so `/kit:start-next` can pick them up on its own, and an out-of-scope section so each ticket stands as its own brief. |
| `kit:writing-tickets` | Lean issues that state the problem and the decision without freezing an implementation. |
| `kit:ticket-artifacts` | Where a plan, brief, or walkthrough is stored and how it's found again. One marked comment per kind on the issue is the store — updated in place, so an issue never accumulates superseded copies — and gitignored `plans/<n>-<kind>.md` is a cache of it. Collapses three storage rules and three recovery paths into one, and gives the walkthrough a life beyond the worktree it was written in. |
| `kit:argument-pages` | A self-contained HTML page arguing one technical position — a schema proposal, a design comparison, a review whose evidence is spread across files the reader would otherwise have to open. Its one rule is that nothing on the page is asserted from memory: every code block is emitted output, every claim carries a `file:line`. Owns the six moves (verdict first, then objects, insight, worked example, mechanism, recommendations), the honesty gates that keep a persuasion device fair, and `ENTITY-DIAGRAM` — hand-built table cards rather than mermaid, so a row can be tinted and a column badged. Publishes as an artifact where the tool exists, else into `plans/`. |
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
