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
| `/kit:prune-specs` | Walks the whole spec suite, one subagent per file, applying `kit:rails-load-bearing-specs`, then **proves** the strongest band by mutation: break the code an example's assertion reaches, run that example, record whether it went red, revert with `git checkout --`. Deleting a spec produces a diff that cannot fail, so the gate is what gives an executor a check at all — applied before the deletion, not after. Not the axis's runtime witness and no substitute for one. A **restated declaration** skips the gate and is proven by its two lines quoted together. Fills any room in the band with **misplaced assertions**, proven by one mutation that runs the owning layer's specs too, then **subsumed** pairs from the same spec directory, proven across several mutations. Files one `technical-debt` ticket and settles it through `/kit:triage` in the same run; decides, never deletes. |

### Building it

| Command | What it does |
|---|---|
| `/kit:list` | The open tickets a sweep would actually start, under the labels you name — number and title, and nothing else. Reads the same `kit:startable-tickets` rule `/kit:ship-ticket` sweeps on, so a ticket it names is one `/kit:ship-ticket <number>` will take. Creates nothing and touches no worktree. A label holding nothing startable reads differently from a label nobody created. |
| `/kit:ship-ticket` | Orchestrates the rest: a reclaim sweep, then worktree, plan, TDD, a simplify pass, PR. Opens by reclaiming dead worktrees in a subagent — ahead of selection, and even when it goes on to take no ticket; what it reclaimed and held is the first line of the report, and a sweep that fails never stops a ticket starting. **Takes one ticket per invocation**: the issue number you name; or a label, which narrows the backlog sweep without replacing its rules; or nothing, and picks the next epic ticket whose blocking edges have all closed. More than one number is a usage error and there is no flag that takes a set — `/kit:list` is how you see what to work on, and running several in succession is the caller's job, one process each. `--dry-run` resolves the selection, reports the ticket and what was excluded, and creates nothing. A trailing `unattended` replaces every gate with a rule; where a rule cannot decide — the plan's anchors have moved, no plan exists, the work won't converge — it **parks**, which is the only way it stops and what makes `/loop` over it safe. Skips any ticket already carrying `kit-blocked`, reported by name with its reason, and any carrying `epic`, which is a container with no slice to implement. |
| `/kit:polish-ticket` | Runs a catch-all polish ticket. The user reports problems one at a time; each is triaged into an inline fix on the branch or its own filed ticket. |
| `/kit:commit` | Focused commit with a real message. Reads the project's test, lint, and security gates from `CLAUDE.md`/manifest/CI and runs them on what changed. |
| `/kit:new-pull-request` | Opens a PR whose body `kit:visual-pr` writes — the Gist-first sections `kit:visual-review` reads — wired to the issue. |
| `/kit:observe` | Records something that surfaced mid-work as a claim the repo can contradict, the command that tests it, and that command's answer now — appended to a store outside version control at the main checkout, so it survives the worktree it was written in. `list` reports what has accumulated and how full the drawer is; `triage` re-runs every check and clears down what the repo has moved past. |

`plugins/kit/scripts/ship-startable.sh <label>` is the runner that works a whole
label without a human re-invoking `/kit:ship-ticket` after every ticket — a
fresh `claude -p` per ticket, so none of them runs in a context that carried a
previous one, taken from `/kit:list`'s output rather than parsed from
ship-ticket's own report. Run it directly in a terminal and leave; see
`docs/shipping-on-a-runner.md`.

### Reviewing and merging

| Command | What it does |
|---|---|
| `/kit:review-copilot` | The unattended half. Takes automated review findings one at a time and verifies each against the code before acting, recording the reasoning for every one in the commit body. A CI gate calls it with `unattended` once a review has landed on a PR — see [tending on a CI runner](tending-on-a-runner.md). |
| `/kit:start-review` | The other side of the workflow: a PR arrives and you have to judge it. Checks the branch out in its own worktree, runs the headless reviewer, and walks the app. Assess-only on a colleague's PR; a fix loop on your own. |
| `/kit:walkthrough` | Verifies a branch in-app one step at a time, against a checklist derived from the issue's acceptance criteria and the diff. The position lives in a file, so a bug found mid-walk detours into triage and returns to the same step. |

### Housekeeping

| Command | What it does |
|---|---|
| `/kit:worktree-gc [target]` | Reclaims worktrees by hand — one named target, or a sweep of all of them. The same sweep runs on its own at the top of every `/kit:ship-ticket`; this is how you ask for one in between. Removes a worktree when it is free, and deletes its branch only where GitHub accounts for the tip. Sweeps the untracked husks `git worktree remove` leaves behind. |
| `/kit:triage-memory-run` | The same pass for auto-memory. Bins every memory as stale, workflow, duplicate, or unclassified, then clears it down — moving what's worth keeping into an on-demand `WORKFLOW.md` and archiving before deleting. `--dry-run` reports what you'd get back and what you'd lose, without writing anything. |

### A command another prompt hands off to needs a `description`

Claude Code merges commands into the same listing as skills, but a command with
no `description:` in its frontmatter is absent from that listing — and the Skill
tool accepts only names the listing carries. So a prompt telling the agent to
invoke an undescribed command produces a refusal and a hand-back asking the user
to run it themselves, which is the whole handoff lost. Nothing fails loudly: the
call site reads fine and the refusal comes at run time, with nobody watching — so
give the command a description in the same change as the handoff.

Reading the command file by path is not the fallback it looks like. `$ARGUMENTS`
stays unsubstituted and the frontmatter is ignored, so the agent imitates the
command instead of running it. A handoff reaches its target through the Skill
tool, under the name the tool takes — `kit:design`, with no leading slash — or it
does not reach it at all.

**The test is per call site, not a fixed list.** A command needs a description
when some prompt tells the agent to invoke it; `design`, `commit`,
`new-pull-request`, `review-copilot` and `worktree-gc` carry one because that is
true of them today. Adding a handoff is what adds a target, so check the one you
are writing rather than trusting this sentence to still be exhaustive.

**Naming a command is not handing off to it.** A prompt that offers the user a
command, or cites one to say where a boundary falls, needs nothing from the
listing — the slash form is the right spelling there, because a person is who
reads it. Only an imperative aimed at the agent is a handoff.

A command nothing hands off to has no `description`, deliberately. Those are
entry points a person invokes by name, and an entry point that self-starts is the
failure the omission prevents. It is also why each description's "Use when" names
its callers rather than its topic: being listed is what would otherwise let the
model reach for the command on a subject nobody handed it.

`disable-model-invocation: true` would guarantee no command self-starts, but it
also blocks a scheduled task whose prompt *is* the command — which is how
`/loop 20m /kit:ship-ticket unattended` and `ship-startable.sh` run — so staying
unlisted is the weaker tool that costs nothing.

## Skills

| Skill | What it does |
|---|---|
| `kit:behavior-placement` | Where behavior belongs — model, domain object, or service — and whether the app already derives the answer. |
| `kit:rails-codebase-design` | The axis `/kit:design` scores approaches on: the six properties of a well-shaped object, the counts that fire when one is missing, and an explicit list of what is *not* a finding — so a pass doesn't manufacture dependency-injection friction a Rails codebase never had. |
| `kit:rails-load-bearing-specs` | The axis for judging one RSpec example: whether breaking the code it covers would break it. Three categories that convict a deletion candidate, each with the evidence it needs, and a not-a-finding list that is the load-bearing half. The unit of a finding is a single `it`, never a file. |
| `kit:rails-excludable-specs` | The companion axis: whether a load-bearing example may be left out of the default suite run. Rarity of the covered path and cost of the run, each with its evidence, and both required — slow alone is on its not-a-reason list. States how excludable differs from deletable, and the convention: a tag that excludes an example, and the runner argument that opts it back in. |
| `kit:asking-a-human` | The axis for a question a pass puts to a person, in the role `kit:rails-codebase-design` plays for object shape. The register belongs to the reader, and the evidence is the **reach** — the entry points that get to the thing being decided, enumerated from source and never weighted, because whether a path is travelled is the reader's to say. "I searched and nothing declares a path to this" is a valid answer and usually names the defect. `kit:park` holds a park's comment to it, and the attended turns in `/kit:design`, `/kit:triage` and `kit:grilling` hold their questions to it. |
| `kit:improve-codebase-architecture` | The scan `/kit:architect` opens with when the topic is "this area feels wrong". Walks an area for the counts in `kit:rails-codebase-design`, discards everything on its not-a-finding list, and publishes an HTML report to `plans/` ranked strongest to weakest. Adopted from mattpocock/skills; the local fork swaps upstream's module/depth/seam vocabulary for the one `kit:rails-codebase-design` defines, makes "name the caller it costs" a gate rather than a nicety and pairs it with the **reach** a chooser ranks on — the entry points that get to the candidate, stated but never weighted, and reported as searched-and-not-found rather than discarding the candidate — writes the report into the repo instead of `$TMPDIR` where it is unrecoverable, and **files its `Strong` band as tickets under an `epic`** — the children carry the empty blocking marker and the `improve-codebase` kind, and the run walks them through `/kit:triage` strongest first, so `/kit:list improve-codebase` names the settled ones and `/kit:ship-ticket <number>` takes them one at a time. Everything below that badge stays on the page as an offer. |
| `kit:domain-modeling` | Writing the project's glossary and its ADRs, at the three points where the model actually changes: a term argued in `/kit:architect`, a concept named or an alternative rejected in `/kit:design`, and the two artifacts a `kit:improve-codebase-architecture` scan leaves behind. Owns both formats: `CONTEXT-FORMAT` for a glossary entry, `ADR-FORMAT` for a decision. Adopted from mattpocock/skills; the local fork names where it's reached from and adds one gate upstream lacks — **an ADR must not restate a mechanism a doc already owns**, which is the way these directories actually rot. |
| `kit:grilling` | The confirmation pass over a converged direction or a ticket's boundary. Adopted from mattpocock/skills; the local fork diverges hard. It fences the pass to what the change actually builds and parks everything adjacent, and it **asserts rather than interrogates** — stating what it takes to be true with the evidence, so the user corrects rather than answers. A question is earned only where choosing differently changes performance, testability, or maintainability, and then it carries one alternative rather than a menu. An edge case that cannot name the input and the path reaching it is not raised at all. |
| `kit:to-tickets` | Cuts an epic into tracer-bullet tickets, each declaring which tickets must merge before it can start. Adopted from mattpocock/skills; the local fork adds a machine-readable edge marker so `/kit:ship-ticket` can pick them up on its own, an out-of-scope section so each ticket stands as its own brief, and a final **walkthrough ticket** for the sets whose composed result only a person can judge — blocked by every slice, routed to a human, its acceptance the walk itself, and continuing as a `/kit:polish-ticket` when the walk finds something. |
| `kit:show-me` | Explains the current topic visually — pseudocode, a call or component tree, a Mermaid diagram, a shape-matched `diff`, or one focused HTML page — picking the smallest view that makes the point. User-invoked only (`/kit:show-me`). Adopted unchanged from humanlayer/skills. |
| `kit:writing-tickets` | Lean issues that state the problem and the decision without freezing an implementation. |
| `kit:ticket-artifacts` | Where a plan, brief, or walkthrough is stored and how it's found again. One marked comment per kind on the issue is the store — updated in place, so an issue never accumulates superseded copies — and gitignored `plans/<n>-<kind>.md` is a cache of it. Collapses three storage rules and three recovery paths into one, and gives the walkthrough a life beyond the worktree it was written in. |
| `kit:shape-review` | Judges the object shape one pull request's diff introduces, placement included, on `kit:rails-codebase-design` — the reviewer for a PR whose author was an unattended agent, where `kit:visual-review` defers placement to the author. Prints one marked comment for a person to post or edit, and changes nothing; `/kit:review-copilot` addresses a posted one on the PR's own branch. Run it as `/kit:shape-review <pr>`; `kit:ticket-loop` `hand-off` runs it too. |
| `kit:reshape` | The in-flight reshape a shape hold offers. Ranks moves across the namespaces the held PR touched, each with the call sites outside the diff it would reach, and commits the one the person picks on the held branch, with no ticket — or files it as a ticket blocked on the issues the held PR closes. `kit-hold` stays. |
| `kit:argument-pages` | A self-contained HTML page arguing one technical position — a schema proposal, a design comparison, a review whose evidence is spread across files the reader would otherwise have to open. Its one rule is that nothing on the page is asserted from memory: every code block is emitted output, every claim carries a `file:line`. Owns the six moves (verdict first, then objects, insight, worked example, mechanism, recommendations), the honesty gates that keep a persuasion device fair, and `ENTITY-DIAGRAM` — hand-built table cards rather than mermaid, so a row can be tinted and a column badged. Publishes as an artifact where the tool exists, else into `plans/`. |
| `kit:startable-tickets` | What makes a ticket one an agent may pick up unbidden — the `ready-for-agent` candidate query, the five conditions, and what `epic`, `kit-blocked`, and the `kit-blocked-by` marker each mean. One home for a rule more than one command reads, and it owns the batched lookups too — the candidate query's explicit `--limit` matters, because `gh issue list` truncates at 30 newest-first and the tickets it drops are the lowest-numbered ones a sweep is defined to take. |
| `kit:start-ticket` | Reads an issue, creates an isolated git worktree off `origin/main` — or delegates to your project's own worktree command — wires up gitignored runtime files, and applies the qualification test that decides whether the approach is settled: a **plan** must exist, as the marked comment or written inline in the body. A body that merely reads as settled does not qualify. Shared mechanism rather than an entry point — `kit:ticket-loop` invokes it as its first phase and goes further. |
| `kit:ticket-loop` | The five phases between a chosen ticket and an open PR — `prepare`, `tdd`, `simplify`, `open-pr`, `hand-off` — and the one substitution that separates attended from unattended: a gate is a question when someone is there, a rule when nobody is, and a `kit:park` where no rule decides. Shared mechanism rather than an entry point; `/kit:ship-ticket` picks the ticket and invokes this. Its phase ids are the handle `/kit:polish-ticket` and `/kit:walkthrough` re-enter at. |
| `kit:park` | The stopping shape every unattended command uses: comment the *decision* the issue needs rather than the symptom, apply `kit-blocked` with the reason in the body, leave the worktree and its commits in place, report it. Owns the two failures either side of it — guessing to avoid a park, and parking to avoid thinking — and the rule that a park inside a nested command is not parked twice. Because it writes to GitHub it needs no memory, which is what makes `/loop` over an unattended pass safe. |
| `kit:worktree-reclaim` | The other end: reclaiming a worktree, one named target or a sweep, attended or not. Splits the directory from the branch — a checkout is restorable in one command, so freeing one costs nothing, while a branch is deleted **only where GitHub accounts for its tip**. That test is why the skill exists: a squash-merge and work that was never pushed produce an identical `git branch -d` refusal, and every previous copy read it as the first and force-deleted the second. Its mechanical half is `scripts/worktree-reclaim.sh`, pinned by `tests/worktree-reclaim.sh` against throwaway repositories. |
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
`kit:start-ticket` is marked as an example to adapt. If you hit an assumption that
isn't marked, that's a bug.

`kit:start-ticket` resolves paths with `git rev-parse --show-toplevel`, so there's
nothing machine-specific to edit before use.

**A ship gate is opt-in.** A project whose merge needs a locally posted status — a
signoff its CI cannot produce — names the command that posts it under
`## Ship gate` in `CLAUDE.md` (`- run: bin/ci`). `kit:ticket-loop` `hand-off` runs
it once, after the review round's last push, and a non-zero exit keeps the PR in
draft. A project without the section never runs its full suite from the loop.

**Review sources are declared too.** `## Review sources` in `CLAUDE.md` lists the
automated reviews a project runs (`- copilot`, `- claude-review`); absent, both
are expected. `hand-off` waits only on what it lists, and the round reports an
unlisted source as not run rather than missing.

**So is whether drafts run the full checks.** `## Draft checks` with `- full`
tells `hand-off` that a draft's green is the ready PR's verdict, so it arms
auto-merge the moment it marks the PR ready instead of first waiting for the
transition's run to register. Absent, it waits — the safe reading for a project
that skips steps on drafts under the same check names.

**External commands these call.** Beyond the [companion skills](companion-skills.md),
the workflow invokes `/simplify` (`kit:ticket-loop` `simplify`), `/loop` (drives
`/kit:ship-ticket` over the backlog), and optionally `/target-debug` (reads the `tickets/` notes
`/kit:new-pull-request` writes). Each degrades to a skipped step if you don't have
it, rather than failing.
