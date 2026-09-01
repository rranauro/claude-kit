---
model: opus
---

Attended ticket workflow: clean-main check → worktree → TDD → simplify → PR, then hand off to `/kit:tend-prs` for review triage, auto-merge, and cleanup.

**Arguments:** `$ARGUMENTS` — GitHub issue number (e.g. `/kit:ship-ticket 612`) or issue URL. Required.

---

## What this skill is

A thin orchestrator. Each phase delegates to an existing skill. **Do not re-implement** what those skills already cover — invoke them via the Skill tool and pass through arguments. This file is the only place the *sequencing*, *gates*, and *handoffs between phases* live.

**This skill covers the attended half only — up to an open PR.** Everything after
that (waiting for the reviewers, triaging findings, enabling auto-merge, removing
the worktree) needs no one present and belongs to `/kit:tend-prs`, which sweeps
every open PR on a loop. Don't reintroduce those phases here; a session that has
to stay alive to finish a ticket is the problem that command exists to solve.

Constituent skills:
- `kit:start-ticket` — `clean-check`, `worktree`, `read-plan`
- `/kit:commit` — invoked inside `tdd` as needed
- `kit:behavior-placement` — `tdd`, when the change adds or moves a class
- `/simplify` — `simplify-pass`
- `/kit:new-pull-request` — `push-and-pr`
- `/kit:tend-prs` — everything after `hand-off`, out of session

---

## Mandatory constraints

- **Do not duplicate constituent skill bodies.** If a phase says "run `/kit:commit`", invoke the Skill tool — do not inline its steps.
- **Halt at every gate.** Gates are explicit user checkpoints (`read-plan` plan approval, `push-and-pr` push approval). Do not skip them in the name of momentum.
- **Worktree-prefixed paths.** Once `worktree` creates the worktree, every Read/Edit/Write must target the path `kit:start-ticket` `create-worktree` resolved. The tool cwd stays at the main checkout.
- **Never merge locally.** PRs merge on GitHub only — via `gh pr merge`, never `git merge` into main.
- **Never run a test directory or the full suite without permission.** Named files and examples only; a path argument with no filename needs an ask. CI runs the full sweep on the PR.

---

## Phase 1 · `clean-check` — Clean-main check

Delegated to `kit:start-ticket` `safety-check`. Before invoking, confirm `$ARGUMENTS` is an issue number/URL; if missing, ask the user.

---

## Phase 2 · `worktree` — Worktree off `origin/main`

Delegated to `kit:start-ticket` `fetch-issue` through `worktree-paths`. Branch name derives from the issue title: `<issue>-<short-description>`. The user confirms it inside `kit:start-ticket`.

After it returns, you will be operating against the worktree path it resolved.

---

## Phase 3 · `read-plan` — Confirm the approach is settled

Delegated to `kit:start-ticket` `plan-implementation`. It takes the settled approach from either artifact that carries one — the stored `plan`, which `kit:ticket-artifacts` resolves from the local cache or the issue comment, or an issue specified enough to stand as its own brief — asks whether it's still fresh, runs its anchor-verification pass when it isn't, then summarizes and asks whether to proceed. If neither exists, it invokes `/kit:design` scoped to this issue. Do not improvise a plan here, do not require a plan when the issue already says what a plan would, and do not read `plans/` directly — a missing file is not a missing plan.

`kit:start-ticket` `placement-check` skips itself when this skill is the caller, and `handoff` after it is a no-op here. `tdd` below owns the placement check.

**Gate:** do not start `tdd` until the user has accepted the plan.

---

## Phase 4 · `tdd` — TDD implementation

Not delegated — this is the work itself.

Use the project's own test framework and layout — read them from `CLAUDE.md`, the
manifest, or CI config rather than assuming. The Rails/RSpec form is shown below
as the worked example; substitute the equivalent for your stack.

**Test placement — extend before adding.** For each requirement in the plan, find the existing test that covers the surface you're touching:

- Modifying an existing method → extend its existing test file. Add a new group/context block, not a new file. *(Rails: `spec/<type>/<name>_spec.rb`, a new `describe`/`context`.)*
- Adding a new public method to an existing class → same as above; a new group for that method in the existing test file.
- Adding a brand-new unit (class, module, component) → create a matching new test file. The new file is justified because the production unit is new, not because the behavior is new.
- Cross-cutting feature with no obvious owner → ask the user where the test belongs before creating one.

Then, per requirement:

1. Write the test (in the file selected above), in the location the project's convention dictates.
2. Run that single example and confirm it fails as expected — no need to ask permission for targeted runs. *(Rails: `bundle exec rspec <path>:<line>`.)*
3. Implement the minimal change. Re-run the example; confirm green.
4. Run the broader test file for regressions — still no need to ask. Naming another *file* is fine; widening to its directory is not, and needs an ask.
5. When the implementation is complete (or at sensible checkpoints), invoke `/kit:commit` via the Skill tool. Do not push from inside it. If the project registers a commit-time gate hook, expect `/kit:commit` to be blocked and to fix what it reports before retrying — that's the gate working, not a failure.

Apply the project's own rules from `CLAUDE.md` while implementing. This skill does not restate them.

When the change adds or moves a class, run the `kit:behavior-placement` skill before
writing it — model, value object, or service, and whether the app already
derives the answer.

---

## Phase 4b · `simplify-pass` — Simplify pass (before the PR exists)

Specs are green; the PR is not open yet. Invoke `/simplify` via the Skill tool
on the working diff, then commit any cleanups it applies.

This runs **here, not later**, because cleanups landing now become part of the
original commits instead of review-response commits — and because the automated
reviewers that run once the PR opens hunt bugs, not duplication. Reuse,
over-abstraction, and altitude problems are exactly what they under-report and what costs a
round-trip when the user catches them by hand.

Do NOT run `/code-review` here. Opening the PR already reviews this diff twice
(Copilot + the Claude headless hook); a third bug-hunt over the same lines buys nothing.
`/simplify` is quality-only, which is why it doesn't overlap.

If `/simplify` proposes a change that contradicts the ticket's agreed approach,
surface it to the user rather than applying it — this pass tidies the
implementation, it does not relitigate the design.

---

## Phase 5 · `push-and-pr` — Push and open PR (gated)

**Gate before pushing.** Ask the user:

> "Ready to push and open the PR, or do you want to boot the worktree and exercise the change in-app first?"

- If they want to test in-app first: offer `/kit:walkthrough <issue>`, which derives a checklist from the AC and the diff and walks it one step at a time, keeping its position on disk so a bug found mid-walk doesn't lose the place. If they'd rather drive unaided, pause and wait for them to come back and approve.
- If they approve the push: invoke `/kit:new-pull-request` via the Skill tool.

`/kit:new-pull-request` already includes `Closes #<issue-number>` automatically when the branch starts with the issue number — verify this happened in the PR body it produced. If the closing keyword is missing (e.g. issue was not the branch prefix), edit the PR body with `gh pr edit <N> --body` to add it. The closing keyword in the **body** is what auto-closes the issue; the title prefix doesn't count.

**Do NOT enable auto-merge here.** The initial PR is opened with auto-merge **off**. CI is fast and will frequently go green before Copilot/Claude reviews land — enabling `--auto` at creation time can merge the PR before reviewers post. Auto-merge is set in `auto-merge`, only after the initial review pass has been addressed and pushed.

---

## Phase 6 · `hand-off` — Hand the PR to the unattended loop

This skill ends here. The PR is open, auto-merge is deliberately off, and both
reviewers post asynchronously after `gh pr create` — Copilot within a few
minutes, the Claude headless review whenever its `claude -p` run finishes.
Waiting for that inside this session means holding it open for an indeterminate
stretch to do work that needs no one present.

`/kit:tend-prs` does the rest: it catches the review round, triages every finding
via `/kit:review-copilot`, pushes the fixes, enables auto-merge unless something
warrants your attention, and removes the worktree once GitHub merges. It is
stateless and sweeps *every* open PR you own, so it does not need to be told
about this one.

Tell the user:

> "PR #<N> is open with auto-merge off. Reviews land in the next few minutes.
>
> If `/loop 20m /kit:tend-prs` is already running, this PR is picked up
> automatically — nothing to do. Otherwise start it, or run `/kit:tend-prs` once
> by hand after the reviews post."

Then stop. Do **not** start the loop from here without being asked: `/loop` binds
to a session, and silently starting a second one in a session the user is about
to leave gives them two sweepers and no clear owner.

**Why no polling gate anymore.** Earlier versions polled Copilot for 10 minutes
from this session, then triaged, merged, and cleaned up in-line — four phases that
all required the user to still be sitting there. Every one of them is now
`/kit:tend-prs`'s, which runs whether or not anyone is.

---

## Failure / interrupt handling

- If any phase fails (spec won't go green, gates won't pass, push rejected), stop at that phase and surface the state. Do not skip ahead.
- If the user interrupts mid-skill, the constituent skills' commits and worktree leave the workspace recoverable. Resume by re-invoking the appropriate phase's skill directly (e.g., `/kit:new-pull-request` to pick up at `push-and-pr`).
- The skill is idempotent at phase boundaries: re-running `/kit:ship-ticket <same-issue>` after partial progress is safe — it will detect the existing worktree and PR.
