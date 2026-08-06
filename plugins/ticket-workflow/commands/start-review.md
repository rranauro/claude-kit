---
model: opus
---

Review someone else's pull request — or your own before anyone sees it — in a dedicated worktree, so the branch can be exercised in a running app without disturbing your own work.

**Arguments:** `$ARGUMENTS` — a PR number or URL. Required.

Each step below carries a stable id in backticks (`read-pr`, `fire-review`, …).
Those ids are the handle other commands reference. Renumber freely; **never
rename an id** without updating the references.

---

## What this is

`/kit:review-copilot` addresses findings on a PR you are already shipping. This is
the other direction: a PR arrives, and you have to form a judgment about it.

Two flows run off the same steps, forked on authorship:

- **Colleague's PR** — the author is the subject-matter expert. The goal is to
  confirm the PR does what it intends and surface genuine concerns as questions.
  Not to fix their code.
- **Your own PR** — the same pass, used as self-review: catch what a colleague
  would flag, then fix or discard it before they spend attention on it.

---

## Step 1 · `read-pr` — Read the PR and establish the lens

Fetch with `gh pr view <n> --json number,title,author,baseRefName,headRefName,body,files`.

Read **the PR's intent**: the author's description *and* the acceptance criteria
of any ticket it closes. That intent is the lens for every later finding — a
concern outside it is at most a one-line question, because any mature codebase
has latent problems and surfacing them here drowns the ones that matter.

Present a short summary including the intent.

**Whose PR is this?** Compare the author to `gh api user -q .login`. Never
hardcode a login. If the comparison can't be resolved, treat it as a colleague's
PR — that branch withholds posting rather than publishing uninvited.

**Has Copilot already reviewed it?** Check
`gh api repos/{owner}/{repo}/pulls/<n>/reviews` and `.../pulls/<n>/comments`,
filtering for a `user.login` containing `copilot` **case-insensitively** — the
inline bot is `Copilot` and the review bot is
`copilot-pull-request-reviewer[bot]`, and a case-sensitive match silently misses
the inline half.

On your own PR, note that the hook-posted review almost always *predates*
Copilot: it fires at `gh pr create`, and Copilot takes 2–5 minutes. So the
existing review usually has no Copilot reconciliation in it. If Copilot has
since posted, offer a second pass — don't force one.

---

## Step 2 · `create-worktree` — Check the branch out beside your work

```
git fetch origin pull/<n>/head:pr-<n>-review
```

Then create the worktree for `pr-<n>-review` per the `kit:worktree-conventions`
skill: delegate to the project's create command if it has one, otherwise
`git worktree add .claude/worktrees/pr-<n>-review pr-<n>-review`. Resolve the
resulting path from `git worktree list --porcelain` — a review worktree in the
wrong place can't boot the app, and booting it is the entire point.

Skip the base check the skill describes. A review branch is the PR's head; it is
supposed to sit where the author left it, not on `origin/main`.

If the project's create command already provisions, you are done — it installed
what the app needs. Otherwise wire it up exactly as `/kit:start-ticket`'s
`wire-worktree` step describes: symlink the gitignored files the app needs to
boot — secrets and their keys, `.claude/settings.local.json`, `node_modules` —
from the main checkout. Don't re-derive that list here; a review worktree that
can't boot verifies nothing.

---

## Step 3 · `fire-review` — Start the headless review before provisioning

Wiring dependencies takes minutes and the review has no reason to wait for it.
Unless `collect-review` below finds one already posted, start it detached first:

```
${CLAUDE_PLUGIN_ROOT}/scripts/pr-review.sh --detach --source start-review <n>
```

Run it from the **main checkout**, not the review worktree — the script resolves
its output directory relative to the repo, and the main checkout is what keeps
the artifact alive after the worktree is gone.

`--detach` returns immediately and logs to
`~/.claude/logs/pr-review/<ts>-pr<n>.log`. Tell the user it's running and where
the log is, then go finish wiring the worktree.

---

## Step 4 · `collect-review` — Get the review

**First check whether one already exists.** On your own PRs the
`pr-review-on-create` hook posts it as a PR comment marked
`<!-- claude-pr-review -->`:

```
gh pr view <n> --json comments \
  -q '.comments[] | select(.body | contains("<!-- claude-pr-review -->")) | .body'
```

If that returns a review, use it — don't re-run. It's the persistent copy and it
already lives where colleagues can see it.

**Otherwise collect the detached run** from `fire-review`. It writes to:

```
<main-checkout>/reviews/pr-<n>/claude-review.md
```

Wait for the file rather than re-running — a second invocation duplicates the
work and the token spend. If it never arrives, read the tail of the log for the
failure and report it. **A detached run that dies is silent by construction**;
the log is the only place it surfaces, so never read the absence of an error as
success.

If `fire-review` was skipped (resuming an old session, worktree already there),
run it in the foreground instead — same command without `--detach`.

**Relay a ≤120-word TL;DR. Do not re-expand the review.** A verdict line, AC
alignment, finding counts, the top concern (say so if it's tagged
`suspected-from-code`), whether Copilot has weighed in, and the comment URL or
file path. Then stop. The user reads the summary and asks for whatever detail
they want, at which point you pull only that section. Everything else is pull,
not push.

---

## Step 5 · `walk-the-app` — Verify it running

Static analysis tells you *what to look at*, never *what to conclude*. Before
treating any finding as real, exercise the flow it lives in.

Hand this to `/kit:walkthrough` — it derives observable steps from the acceptance
criteria and the diff, persists the position to disk, and presents one step at a
time so a bug found mid-walk doesn't lose your place. Don't re-derive that here.

Two things this command adds on top:

- **Seed the walk with the author's own instructions.** If the PR body carries
  test steps, those are the list. Don't invent a click path alongside them, and
  don't fact-check their setup — if something in it errors locally, work around
  it quietly. It isn't yours to pin.
- **Add a step for every `suspected-from-code` finding**, so exercising the
  feature confirms or refutes it. That is the only thing that promotes one to a
  verdict.

If the PR closes no issue, `/kit:walkthrough` has no acceptance criteria to derive
from — say so and walk the author's instructions directly.

---

## Colleague's PR — `assess-only`

**Assess Copilot; don't act on it.** If the author received a Copilot review,
form your own read on each comment and note whether the author addressed it.
You may run `/kit:review-copilot <n>` in analysis-only mode to triage them — **never
its fix-and-push path.** We do not fix another person's PR.

**Drafting comments.** Never post anything without the user's explicit
permission. Inline comments stay in a pending review; never submit it unless
they say submit. Frame findings as questions that leave the author latitude to
acknowledge, defer as out of scope, or ignore — unless it's a degenerate case
they genuinely should fix. One or two sentences each, no tables or heavy markup,
so the user can paste straight into the review box.

---

## Your own PR — `self-review`

**Triage every finding** into fix / discard (with a one-line reason) / defer
(tracked as a follow-up ticket). Keep a running note in the PR description under
a `## Self-review notes` heading, so reviewers can see the thinking already done
and skip re-raising it:

```markdown
## Self-review notes
- Addressed: N+1 in the panel query, missing index on the join column
- Discarded: suggested rename of `matches?` — existing callers rely on the name
- Deferred to #1187: extract the scopes presenter
```

**Then act on Copilot** — if the review flagged any of its comments as worth
acting on, run `/kit:review-copilot <n>`, which verifies each against the code,
applies the valid ones, runs the affected tests, and records every decision
including the rejections. Skip it if reconciliation already disagreed with all
of them.

**Fix, then push.** Apply edits in the review worktree or your feature worktree
— your call — run the project's tests and linter on what changed, and exercise
the feature in the running app. If the fix set was non-trivial, re-run
`/kit:start-review <n>` on the updated HEAD for a second pass.

---

## Step 6 · `teardown` — Ask, don't assume

**Do not tear the worktree down on your own.** The user may want it as a
sandbox across sessions. Ask:

> "Review worktree `pr-<n>-review` is still on disk. Remove it, or keep it?"

On explicit approval, follow `/kit:cleanup-worktree`'s semantics — the project's
remove command if it has one, otherwise `git worktree remove [--force]` plus a
sweep of the path for the runtime files git leaves behind, then
`git worktree prune` — and finally `git branch -D pr-<n>-review`
(the local review branch was never merged; `-d` will refuse it, and that refusal
carries no information here).

The artifacts under `<main-checkout>/reviews/pr-<n>/` are **not** touched by
worktree removal. That's the point of writing them there. Remove that directory
only if the user asks to clear the artifacts too.
