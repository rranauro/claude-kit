---
model: opus
license: MIT — Copyright (c) 2026 Ron Ranauro, https://github.com/rranauro/claude-kit
---

Unstick a pull request that has stalled on a merge conflict: bring the base into
its branch, resolve the conflict, check what the conflict touched, push, and run
the project's ship gate once, on the pushed resolution.

**Arguments:** `$ARGUMENTS` — a PR number or URL. Required.

Run it from the main checkout.

**Attended only.** A trailing `unattended` is a usage error: report it and start
nothing. A pass may not bring the base into its branch (`kit:ticket-loop`'s
never-integrate constraint), so a PR that has fallen behind is the operator's to
carry forward. This command is how they carry it, and their invoking it is the
authorization.

**Check cheaply before the push, and gate once after it.** A gate run before the
push tests a head the PR doesn't have yet, so its status can never count
(`docs/commands.md` *A ship gate is opt-in*). The check before the push is
there to catch a resolution that breaks the code it touched.

---

## Step 1 · `locate` — A checkout of the PR's branch

`gh pr view <n> --json state,headRefName,baseRefName,closingIssuesReferences`.
If it isn't open, say so and stop.

`<base>` is the PR's `baseRefName`. The PR already names the branch it merges
into, and that wins over `kit:project-rules` *The base branch*.

`git fetch origin <headRefName> <base>` once, then find the worktree on
`headRefName` with `git worktree list --porcelain`. If there is none, create one
as `/kit:start-review` Step 2 does, on `headRefName` itself rather than a
`pr-<n>-review` branch, and skip the base check the convention describes too.
Its offered rebase is the operation Step 2 rules out. Hold the absolute path as
`<worktree>`. Every Read/Edit/Write from here targets it, and the tool cwd
stays at the main checkout.

**A worktree with uncommitted changes stops here.** Say what is dirty and let the
person deal with it. A merge started over someone's work in progress mixes the
two.

**Then make it current.** If the local branch is behind `origin/<headRefName>`,
fast-forward it. If the two have diverged, ask before doing anything. A
resolution merged onto a stale local tip pushes as a rejected non-fast-forward,
or worse, a forced one.

**Take the lease**, as `kit:start-ticket` `create-worktree` does. Key it on the
issue the PR closes, or on the PR number where it closes none. Once the merge
commit exists the worktree is clean again, and a sweep running elsewhere would
otherwise reclaim it between the push and the gate. Release it however the
command ends, with `git worktree unlock <worktree>`.

## Step 2 · `merge` — Bring the base in, and resolve

`git -C <worktree> merge origin/<base>` — a merge, never a rebase. A rebase
rewrites the commits the PR's review round was decided against and needs a
forced push. A merge commit adds one commit on top, and a squash merge folds it
away.

**A merge that comes back clean means there was no conflict.** GitHub had not
recomputed, or someone resolved it already. Say so, `git -C <worktree> merge
--abort`, and stop. A PR that is merely behind is GitHub's to update.

Record the conflicted paths before touching anything:
`git -C <worktree> diff --name-only --diff-filter=U`. Step 3 checks exactly these.

Resolve each one. Where a resolution is mechanical, such as both sides adding
neighbouring lines or a rename on one side, resolve it and say how. **Where the
two sides disagree about behavior, show the person both and ask.** Choosing
between two intents is the decision this command exists to put in front of
someone.

## Step 3 · `check` — What the conflict touched, before the push

Take the project's gates as `/kit:commit` Step 3 identifies them, and run them as
its Step 4 does, on **the conflicted paths from Step 2 only**, not the branch's
whole diff against the base. Named files and examples only, never a directory
and never the whole suite, whether or not the project declares a ship gate.

**A failure is a broken resolution.** Fix it and run again. A failure that won't
clear after a genuine attempt is the person's to decide, so surface it and stop
before anything is pushed: `git -C <worktree> merge --abort` is theirs to run if
they want to start over.

Then conclude the merge: `git -C <worktree> commit --no-edit`, adding a line on
each resolution that was not mechanical. Not `/kit:commit`, since it splits by
concern and a merge commit is one commit.

## Step 4 · `push` — Put the resolution on the PR

`git -C <worktree> push origin HEAD:<headRefName>`. Never `--force`. A rejection
means the remote moved since Step 1, so go back to Step 1's *make it current*
rather than overriding it.

Then read the PR once: `gh pr view <n> --json headRefOid,isDraft,autoMergeRequest,labels`.
Steps 5 and 6 both decide from this read.

## Step 5 · `arm` — Leave the PR armed for the gate to release

Settle auto-merge **before** the gate runs. GitHub keeps auto-merge on across a
push from someone with write access, so a PR armed at hand-off is still armed.

- **Armed** → leave it.
- **Not armed** → decide whether it may be armed, as `kit:ticket-loop` `hand-off`
  step 5 decides it for an open PR (`## Auto-merge`, the repository setting, a
  hold and `## Hold check`, and the method), leaving out its draft transition,
  snapshot and poll. If it may not be armed, leave it and say why. If it may,
  **ask before arming**. An operator's disable stands, and nothing on the PR says
  whether this one was deliberate. A draft stays unarmed. Marking it ready is
  the person's call.

## Step 6 · `gate` — Run the ship gate once, on the pushed head

Run the project's `## Ship gate` as `kit:ticket-loop` `hand-off` step 4 runs it:
once, from `<worktree>`, with nothing committed or pushed after it. **Absent →
skip this step.** CI is the gate.

**First confirm the head.** `git -C <worktree> rev-parse HEAD` must equal the
`headRefOid` from Step 4's read. If it doesn't, someone pushed in between, and a
gate run now would attest the wrong commit. Say so and stop.

- **Zero** → the status is posted, and an armed PR merges on it.
- **Non-zero** → show the person the failing output and leave auto-merge as
  Step 5 left it. The required status keeps the PR unmerged. A fix is an
  ordinary commit through `/kit:commit`, checked on the paths the fix changed.
  Then continue from Step 4, which gives one more gate run.

## Step 7 · `report` — Say what happened

Release the lease, then read the PR once, as `kit:ticket-loop` `hand-off` step 6
reads it, and report what you find, not what you did:

> "PR #<N>: resolved <k> conflicted files (<which were decided by you>), checked
> <what ran>, and pushed <short SHA>. <Ship gate passed | Ship gate failed — the
> output is above, and the PR stays unmerged | No ship gate, so CI decides>.
> Auto-merge <reads on | reads off — <why>>. <Any failing check the rollup names.>"

Leave the worktree in place. Once the PR merges, the next `/kit:ship-ticket` or
`/kit:worktree-gc` reclaims it.
