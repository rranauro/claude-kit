---
model: opus
---

Run a long-lived cleanup/polish ticket: the user drives the UX, feeds observed problems one at a time, and each one is either fixed inline on the branch or split out as its own ticket.

**Arguments:** `$ARGUMENTS` — a GitHub issue number or URL, optionally followed by free-text notes (e.g. an existing worktree path to resume). Required.

---

## What this skill is

A **session shape**, not a linear procedure. Most commands here run start-to-finish; this one opens a branch and then sits in an intake loop for as long as the user keeps reporting things — often across many sessions.

Use it when the issue is a catch-all: "smooth the rough edges before launch", "polish pass on the editor", "fix whatever the walkthrough turns up". Signals: the body has no single deliverable, the acceptance criteria are a checklist of unrelated outcomes, and the labels lean `epic` / `Technical Debt`.

Do **not** use it for a scoped issue with one agreed change — that's `/kit:ship-ticket`.

Constituent skills:
- `kit:start-ticket` — `safety-check` through `worktree-paths`
- `/kit:commit` — once per accepted fix
- `kit:writing-tickets` — for anything split out
- `kit:behavior-placement` — before any fix that adds or moves a class
- `/kit:ship-ticket` — Phase 4b onward, when the branch is ready to land
- `/kit:cleanup-worktree` — after the merge

---

## Mandatory constraints

- **One branch, one worktree, many small commits.** Every fix lands on the cleanup branch. Never commit to `main`.
- **All work happens in the worktree.** Once located, every Read/Edit/Write targets its path — resolved from `git worktree list --porcelain`, not assumed. The tool cwd stays at the main checkout.
- **Ask before editing, every time.** Approval for one fix is not approval for the next. The user is walking the UI; they decide what gets touched.
- **Durable state lives in git and the issue, not in context.** This ticket outlives its sessions. If a decision isn't in a commit message, the issue body, or a filed ticket, it is lost.
- **A ticket is for an unknown fix shape, not for deferring known work.** If you can name the change in one sentence and it meets the inline bar, do it now. Filing a ticket to avoid doing a small fix is the failure mode this skill most easily falls into.

---

## Step 1 · `parse-issue` — Parse the reference

Extract the issue number from `$ARGUMENTS`. If absent, ask.

Keep any free-text remainder — the user often names the existing worktree path or the standing arrangement there ("I'll drive the UX and feed you issues"). Treat that as scope input for `confirm-scope`, not noise.

---

## Step 2 · `locate-work` — Find the worktree, or create it

Delegated to `kit:start-ticket` `safety-check` through `worktree-paths`. Both entry paths route through it:

- **Resuming** (the common case) — `safety-check` finds an existing worktree on an `<issue>-*` branch and offers Resume. Take it. The worktree is already provisioned; do not re-run `wire-worktree`.
- **Starting fresh** — no worktree matches the issue prefix. `kit:start-ticket` creates one off `origin/main` and wires it.

Skip `kit:start-ticket` `plan-implementation` entirely. A cleanup ticket has no settled architecture to hand off, and **do not invoke `/kit:architect` for the epic itself** — that's what `file-ticket` is for, per split-out item. If a `plan` artifact happens to exist, read it as context and move on — the cache file only, and don't spend a `gh` round trip going after the comment when one isn't there.

### Confirm the work is all in one place

Resuming is where this ticket leaks. Before accepting the worktree, verify:

1. `git -C <worktree> status` — clean? Uncommitted changes from a prior session are either work-in-progress the user forgot or a fix that was never committed. Show them and ask which.
2. `git -C <worktree> log --oneline origin/main..HEAD` — the fixes landed so far. This list *is* your memory of the ticket; read it before asking the user what's been done.
3. `git log --oneline origin/main..HEAD` **in the main checkout** — must be empty. Anything here is a fix that landed on the wrong branch.
4. `git worktree list` — exactly one worktree for this issue number. A second is the trap `kit:start-ticket` warns about: the dev server boots in the stale one and fixes read as "not working".

Report the commit list back to the user as the resume summary, then enter `intake`.

---

## Step 3 · `confirm-scope` — Read the issue and state the arrangement

`gh issue view <number>`. Summarize the acceptance criteria, and note which are already satisfied by the commits from `locate-work`.

Then state the working agreement back in one or two lines, so the loop's rules are explicit for the rest of the session:

> "Standing arrangement: you report, I triage. Small fixes land inline on this branch after you approve each one; anything needing a design decision gets filed as its own ticket. Send the first one."

Then **stop and wait**. Do not go hunting for problems to fix. The user drives; unprompted sweeps produce churn they didn't ask for and blow the branch's blast radius.

---

## Step 4 · `intake` — Take one reported problem

The user reports a symptom, usually from the UI: what they did, what they saw, what they expected. Screenshots are common.

Before triaging, get to a **located cause**, not a guess:

- Reproduce or locate the responsible code. Follow the project's own debugging protocol if `CLAUDE.md` names one.
- Converge fast. If two or three focused checks haven't found the cause, stop and say so rather than widening the search — an unlocated cause is itself a triage signal (see `triage`).
- Do not edit anything yet.

One item at a time. If the user reports several at once, list them back, triage each, and work them in the order they pick.

`/kit:walkthrough` enters here when a step it presented surfaced a bug. The loop is
unchanged; the only difference is on the way out — after `fix-inline` or
`file-ticket`, return to that skill's `present-step` rather than to `intake`, so
the user resumes the walk instead of being asked for another report.

---

## Step 5 · `triage` — Inline fix, or its own ticket

The judgment call this whole skill exists for. Decide from the located cause, not from how the symptom looked.

**Fix inline when all of these hold:**
- You can state the change in one sentence.
- It's confined to code you've now read — roughly one file, one template, or one method.
- No new or moved class, no migration, no change to a shared contract (API shape, generator output, component schema, public interface).
- Existing tests cover the surface, or one new example covers it.
- Reverting it is one `git revert`.

**File a ticket when any of these hold:**
- Two plausible fixes exist and picking between them is a design decision.
- The cause is still unlocated after focused investigation.
- It adds or moves a class, changes a schema, or touches a generator, contract, or subsystem you haven't read.
- The blast radius reaches files the user hasn't asked you to touch.
- The user says some version of "we should think about that".

**Ambiguous?** Show the user the one-sentence change and the files it touches, and let them call it. That's cheaper than guessing wrong in either direction.

Say which way you're going and why, in one line, before acting.

---

## Step 6 · `fix-inline` — Make the small fix

1. **Get approval for this specific fix.** State what you'll change and where. A plan-level "proceed" from earlier in the session does not carry; neither does `acceptEdits` permission mode.
2. Write the failing test first if the project's rules call for it (most do for bug fixes) — it's the artifact that proves the symptom was real once the session's memory is gone.
3. Make the change. Run the targeted test. Run the file it lives in for regressions. Targeted runs need no permission; a directory or the full suite does.
4. If the change adds or moves a class, run `kit:behavior-placement` first. Cleanup tickets accrete misplaced helpers precisely because each one looked too small to think about.
5. Invoke `/kit:commit` — **one commit per fix**, subject naming the user-visible symptom, not the internal mechanism. At ship time these commits become the PR body, and future-you reads them to know what this branch did.
6. Hand back to the user to verify in-app, then return to `intake`.

Do not batch several unrelated fixes into one commit. The branch's value as a record is per-fix granularity.

---

## Step 7 · `file-ticket` — Split the bigger ones out

Use the `kit:writing-tickets` skill. State the problem and the desired outcome; do not freeze an implementation — the implementer re-explores the code at `kit:start-ticket` time, and frozen detail rots.

Carry across what only this session knows: the reproduction, the located cause if you found one, and the alternatives you considered. That context is expensive to recover and is the reason the ticket is worth filing rather than just remembering.

Label it as the project does (bug vs. enhancement). Reference the cleanup epic so the trail survives, and note the new issue number back to the user.

If the item needs its *how* settled before anyone can implement it, say so and offer `/kit:design` — but as a **separate** invocation for that item, not for the epic. If the *problem itself* is still open, that's `/kit:architect`, likewise separately.

Then return to `intake`. Do not start implementing what you just filed.

---

## Step 8 · `log-progress` — Keep the issue honest

Cheap, and it's what makes resuming work.

- Tick acceptance-criteria boxes on the epic as commits satisfy them (`gh issue edit`).
- Keep the list of split-out ticket numbers visible on the epic — a comment, or an appended list in the body.

Do this when something meaningful closes, not after every commit.

---

## Step 9 · `ship` — Land the branch

The user calls this, not you. A cleanup ticket has no natural end; ask at natural pauses ("that's the last one I've got for now") whether to land what's on the branch.

Landing does **not** require the epic to be finished. A cleanup branch is better shipped in batches than held open for weeks — a long-lived branch drifts from `main` and its review gets unreviewable.

Hand off to `/kit:ship-ticket` starting at Phase 4b (`simplify-pass`) — `clean-check`, `worktree`, `read-plan`, and `tdd` are already done by this skill's loop. So: `/simplify` over the accumulated diff, then `push-and-pr` and `hand-off` — from there `/kit:tend-prs` triages the reviews, enables auto-merge, and cleans up the worktree out of session.

Two adjustments for a multi-fix branch:

- **The PR body is the fix list.** One line per commit, in the user's terms. Reviewers need to see the scope is many-small, not one-large.
- **`Closes #<epic>` only if the epic is actually done.** Mid-stream batches must not auto-close it — use `Part of #<epic>` instead. This is the most common mistake in this workflow: `/kit:new-pull-request` adds the closing keyword automatically from the branch prefix, so check the body it generates and downgrade the keyword when the epic lives on.

If the epic continues after the merge, `/kit:cleanup-worktree` removes the worktree — and the next batch starts over at `locate-work`, which will create a fresh one off the updated `origin/main`.

---

## Failure / interrupt handling

- **Session ends mid-loop.** Fine by design. Everything accepted is committed; everything deferred is a filed issue. Re-invoke `/kit:polish-ticket <issue>` and `locate-work` reconstructs the state from `git log`.
- **A fix turns out bigger than triaged.** Stop, revert or stash, and re-triage as `file-ticket`. Do not push through a growing change on a cleanup branch — that's how a polish PR becomes unreviewable.
- **The user reports something already fixed on the branch.** Likely a stale server, or the second-worktree trap from `locate-work`. Check which worktree the app is booted from before re-investigating.
- **The branch drifts far behind `main`.** Rebase or ship a batch. Don't let it accumulate silently.
