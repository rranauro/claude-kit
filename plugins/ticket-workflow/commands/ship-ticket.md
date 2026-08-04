---
model: opus
---

End-to-end ticket workflow: clean-main check → worktree → TDD → simplify → PR → automated review (Copilot + Claude headless) → auto-merge → cleanup.

**Arguments:** `$ARGUMENTS` — GitHub issue number (e.g. `/ship-ticket 612`) or issue URL. Required.

---

## What this skill is

A thin orchestrator. Each phase delegates to an existing skill. **Do not re-implement** what those skills already cover — invoke them via the Skill tool and pass through arguments. This file is the only place the *sequencing*, *gates*, and *handoffs between phases* live.

Constituent skills:
- `/start-ticket` — `clean-check`, `worktree`, `read-plan`
- `/commit` — invoked inside `tdd` as needed
- `behavior-placement` — `tdd`, when the change adds or moves a class
- `/simplify` — `simplify-pass`
- `/new-pull-request` — `push-and-pr`
- `/loop` + `/wait-copilot` — `poll-review`
- `/review-copilot` — `evaluate-findings`
- `/cleanup-worktree` — `cleanup`

---

## Mandatory constraints

- **Do not duplicate constituent skill bodies.** If a phase says "run `/commit`", invoke the Skill tool — do not inline its steps.
- **Halt at every gate.** Gates are explicit user checkpoints (`read-plan` plan approval, `push-and-pr` push approval, `poll-review` session-hold approval, `auto-merge` confirmation). Do not skip them in the name of momentum.
- **Worktree-prefixed paths.** Once `worktree` creates the worktree, every Read/Edit/Write must target the path `/start-ticket` `create-worktree` resolved. The tool cwd stays at the main checkout.
- **Never merge locally.** PRs merge on GitHub only — via `gh pr merge`, never `git merge` into main.
- **Never run the project's full test suite without permission.** Targeted runs need no permission.

---

## Phase 1 · `clean-check` — Clean-main check

Delegated to `/start-ticket` `safety-check`. Before invoking, confirm `$ARGUMENTS` is an issue number/URL; if missing, ask the user.

---

## Phase 2 · `worktree` — Worktree off `origin/main`

Delegated to `/start-ticket` `fetch-issue` through `worktree-paths`. Branch name derives from the issue title: `<issue>-<short-description>`. The user confirms it inside `/start-ticket`.

After it returns, you will be operating against the worktree path it resolved.

---

## Phase 3 · `read-plan` — Read the plan file

Delegated to `/start-ticket` `plan-implementation`. The plan lives at `<worktree>/plans/<issue>-plan.md`. If the file exists, `/start-ticket` asks whether it's still fresh and runs its anchor-verification pass when it isn't, then summarizes and asks whether to proceed. If no plan exists, it invokes `/design` scoped to this issue to create one — do not improvise a plan here.

`/start-ticket` `placement-check` is **not** re-run by this skill; `tdd` below owns it.

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
4. Run the broader test file (and adjacent tests if relevant) for regressions — still no need to ask. Only the full suite requires permission.
5. When the implementation is complete (or at sensible checkpoints), invoke `/commit` via the Skill tool. Do not push from inside it. If the project registers a commit-time gate hook, expect `/commit` to be blocked and to fix what it reports before retrying — that's the gate working, not a failure.

Apply the project's own rules from `CLAUDE.md` while implementing. This skill does not restate them.

When the change adds or moves a class, run the `behavior-placement` skill before
writing it — model, value object, or service, and whether the app already
derives the answer.

---

## Phase 4b · `simplify-pass` — Simplify pass (before the PR exists)

Specs are green; the PR is not open yet. Invoke `/simplify` via the Skill tool
on the working diff, then commit any cleanups it applies.

This runs **here, not later**, because cleanups landing now become part of the
original commits instead of review-response commits — and because the automated
reviewers in `evaluate-findings` hunt bugs, not duplication. Reuse,
over-abstraction, and altitude problems are exactly what they under-report and what costs a
round-trip when the user catches them by hand.

Do NOT run `/code-review` here. `evaluate-findings` already reviews this diff
twice (Copilot + Claude headless); a third bug-hunt over the same lines buys nothing.
`/simplify` is quality-only, which is why it doesn't overlap.

If `/simplify` proposes a change that contradicts the ticket's agreed approach,
surface it to the user rather than applying it — this pass tidies the
implementation, it does not relitigate the design.

---

## Phase 5 · `push-and-pr` — Push and open PR (gated)

**Gate before pushing.** Ask the user:

> "Ready to push and open the PR, or do you want to boot the worktree and exercise the change in-app first?"

- If they want to test in-app first: offer `/walkthrough <issue>`, which derives a checklist from the AC and the diff and walks it one step at a time, keeping its position on disk so a bug found mid-walk doesn't lose the place. If they'd rather drive unaided, pause and wait for them to come back and approve.
- If they approve the push: invoke `/new-pull-request` via the Skill tool.

`/new-pull-request` already includes `Closes #<issue-number>` automatically when the branch starts with the issue number — verify this happened in the PR body it produced. If the closing keyword is missing (e.g. issue was not the branch prefix), edit the PR body with `gh pr edit <N> --body` to add it. The closing keyword in the **body** is what auto-closes the issue; the title prefix doesn't count.

**Do NOT enable auto-merge here.** The initial PR is opened with auto-merge **off**. CI is fast and will frequently go green before Copilot/Claude reviews land — enabling `--auto` at creation time can merge the PR before reviewers post. Auto-merge is set in `auto-merge`, only after the initial review pass has been addressed and pushed.

---

## Phase 6 · `poll-review` — Poll for Copilot review (60s, up to 10 min)

**Gate before starting the loop.** This phase holds the current session open for up to 10 minutes. Ask the user:

> "This phase will poll for Copilot's review every 60s for up to 10 minutes — this holds the current session. Continue here, or hand off to a new session?
>
> To hand off: open a new Claude Code session in this repo and run `/wait-copilot <PR#>` (then `/review-copilot <PR#>` once Copilot posts)."

- If they want to hand off: stop here. The PR is open; the user picks up from `/wait-copilot` in the new session.
- If they want to continue: proceed with the loop below.

`/new-pull-request` `start-polling` normally kicks off `/loop 90s /wait-copilot <PR#>`. **Override the interval to 60s for this skill** by invoking `/loop` with args `60s /wait-copilot <PR#>` instead.

Bound: 10 attempts (~10 minutes). If `/wait-copilot` has not signalled "ready" after 10 firings, surface this to the user:

> "Copilot has not posted a review after 10 minutes. Stop the loop with `/loop stop` and decide: keep waiting, ping the PR manually, or proceed without Copilot review?"

Do not silently keep polling past the bound.

---

## Phase 7 · `evaluate-findings` — Evaluate each comment empirically (both reviewers)

Delegated to `/review-copilot`. Despite its name, that skill addresses **all** automated reviewers:
- **GitHub Copilot** — inline + top-level review comments
- **Claude Opus headless review** — posted as a top-level PR comment by the `pr-review-on-create.sh` hook on `gh pr create`, identifiable by the `<!-- claude-pr-review -->` marker

The skill fetches all present sources, deduplicates overlapping `(path, line)` findings into single buckets, and verifies each against the code before acting. Findings flagged by more than one reviewer land in the same bucket and are the strongest signal to act.

Note that `/review-copilot` does not prompt per finding — it applies or skips each one on the evidence and reports a summary, with every decision recorded in the commit body. The user's checkpoint is that summary, not each item.

**Don't run `evaluate-findings` too early.** Both reviewers post asynchronously after `gh pr create`. `poll-review`'s `/wait-copilot` polls for Copilot only; the Claude headless review can land later (it's a fresh `claude -p` Opus run reviewing the diff). Before invoking `/review-copilot`, sanity-check that the Claude review comment exists with `gh api repos/{owner}/{repo}/issues/<PR#>/comments --jq '.[] | select(.body | startswith("<!-- claude-pr-review -->"))'`. If it's missing, wait another ~60s before proceeding — running `/review-copilot` against an absent Claude review just means Copilot-only coverage that pass.

**Empirical verification — applies to every reviewer.** Before accepting any claim, read the offending lines and trace the actual behavior. Common false positives from any reviewer:

- "Missing nil check" on a value that is provably non-nil in this code path.
- "Extract a constant" for something used exactly once.
- "Race condition" flagged in serial code.
- "N+1" against a Rails relation that is already eager-loaded upstream.

When the comment doesn't survive evidence, classify as ⚪ Ignore and record the reasoning in the commit message body — `/review-copilot` `summarize` already requires the per-item evaluation to be durable in git history. Reviewers agreeing on the same `(path, line)` bucket is a stronger signal than one alone — but still verify; they can all be wrong about the same thing.

---

## Phase 8 · `auto-merge` — Auto-merge when green

**Preconditions** — all must be true before this phase runs:
1. First-pass reviewer output has been seen: the Copilot review (or `/wait-copilot` bound exhausted with explicit user decision to proceed) **and** the `<!-- claude-pr-review -->` comment from the headless hook.
2. `/review-copilot` (`evaluate-findings`) has triaged every finding and reported its summary.
3. Any review-response commits are pushed to the PR branch.

`/review-copilot` `enable-auto-merge` defers to this phase when it was invoked from here, so auto-merge is still off at this point and the gate below is the one that decides.

If all three hold, enable GitHub auto-merge:

```
gh pr merge <PR#> --auto --squash
```

GitHub then merges the PR itself once required checks pass. This is the only sanctioned merge path — do not run `git merge` locally and do not prompt the user to.

**One review pass per PR.** After enabling auto-merge, do not re-trigger Copilot/Claude on the response commits and do not re-walk findings. Whatever passes CI on the response push ships.

**Gate before enabling auto-merge.** Confirm with the user:

> "Initial review findings addressed and pushed. Enable auto-merge (squash) for PR #<N>? GitHub will merge once checks pass."

If the user declines (e.g., wants to wait for a human reviewer), stop here. They will merge from the GitHub UI when ready, and `cleanup` can be invoked separately.

If `gh pr merge --auto` errors because auto-merge is not enabled in repo settings, fall back to:
1. Polling `gh pr checks <PR#>` until all required checks succeed or one fails.
2. If green, ask the user to confirm, then run `gh pr merge <PR#> --squash`.
3. If red, surface the failing check and stop.

---

## Phase 9 · `cleanup` — Clean up

After the PR is merged on GitHub (auto-merge has fired, or the user merged manually), delegate to `/cleanup-worktree` with the branch name. It handles:

- Verifying merge state on GitHub
- Confirming the branch isn't checked out elsewhere (always ask)
- `git worktree remove`
- `git branch -d` (safe delete, never `-D` without explicit user approval)
- `git worktree prune` and `git remote prune origin`

If auto-merge is still pending when this skill's session ends, do **not** run cleanup yet. Tell the user: "Auto-merge is set; run `/cleanup-worktree <branch>` once GitHub finishes merging." Do not poll indefinitely.

---

## Failure / interrupt handling

- If any phase fails (spec won't go green, push rejected, Copilot review never lands, auto-merge declined), stop at that phase and surface the state. Do not skip ahead.
- If the user interrupts mid-skill, the constituent skills' commits and worktree leave the workspace recoverable. Resume by re-invoking the appropriate phase's skill directly (e.g., `/new-pull-request` to pick up at `push-and-pr`).
- The skill is idempotent at phase boundaries: re-running `/ship-ticket <same-issue>` after partial progress is safe — it will detect the existing worktree and PR.
