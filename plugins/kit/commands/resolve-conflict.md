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
nothing. A pass may not bring the base into its branch (ADR 0006, and
`kit:ticket-loop`'s never-integrate constraint), so a PR that has fallen behind
is the operator's to carry forward, and this command is how they carry it. A
person invoking it is the authorization. Nothing here substitutes a rule for
them.

## Why the gate runs after the push, and only then

A ship gate posts a status on the SHA it tested (`docs/commands.md`). Run before
the push, it tests a head the PR doesn't have yet, so its status can never
count, and the gate has to run again after the push anyway. Some gates refuse an
unpushed head outright. Pushing first is safe because the gate's status is
required. A resolution that breaks something can be pushed, but it can't merge.

So the work splits in two. A **cheap check before the push** catches a resolution
that breaks the code it touched. The **gate after the push** is the one run that
attests the head.

---

## Step 1 · `locate` — A checkout of the PR's branch

`gh pr view <n> --json number,state,headRefName,headRefOid,baseRefName,isDraft,mergeable,autoMergeRequest,labels`

- **Not open** → say so and stop.
- **`mergeable` is not `CONFLICTING`** → say there is no conflict to resolve and
  stop. A PR that is merely behind is GitHub's to update, not this command's.
  `UNKNOWN` means GitHub is still computing it, so read again once before
  deciding.

`<base>` is the PR's `baseRefName`. The PR already names the branch it merges
into, and that wins over `kit:project-rules` *The base branch*.

Find the worktree on `headRefName` with `git worktree list --porcelain`. If there
is none, create one as `kit:worktree-conventions` says, on the existing branch
(`git fetch origin <headRefName>` first), and wire it as `kit:start-ticket`
`wire-worktree` describes. Hold its absolute path as `<worktree>`. Every
Read/Edit/Write from here targets it, and the tool cwd stays at the main
checkout.

**A worktree with uncommitted changes stops here.** Say what is dirty and let the
person deal with it. A merge started over someone's work in progress mixes the
two.

**Then make it current.** `git -C <worktree> fetch origin <headRefName> <base>`,
and if the local branch is behind `origin/<headRefName>`, fast-forward it. If the
two have diverged, ask before doing anything. A resolution merged onto a stale
local tip pushes as a rejected non-fast-forward, or worse, a forced one.

**Take the lease**, as `kit:start-ticket` `create-worktree` describes. Once the
merge commit exists the worktree is clean again, and a sweep running elsewhere
would otherwise reclaim it between the push and the gate.

## Step 2 · `merge` — Bring the base in, and resolve

`git -C <worktree> merge origin/<base>` — a merge, never a rebase. A rebase
rewrites the commits the PR's review round was decided against and needs a
forced push. A merge commit adds one commit on top, and a squash merge folds it
away.

Record the conflicted paths before touching anything:
`git -C <worktree> diff --name-only --diff-filter=U`. Step 3 checks exactly these.

Resolve each one. Where a resolution is mechanical, such as both sides adding
neighbouring lines or a rename on one side, resolve it and say how. **Where the
two sides disagree about behavior, show the person both and ask.** Choosing
between two intents is the decision this command exists to put in front of
someone.

Don't commit yet.

## Step 3 · `check` — What the conflict touched, before the push

Take the project's gates as `/kit:commit` Step 3 identifies them, and run them as
its Step 4 does, on **the conflicted paths from Step 2 only**, not the branch's
whole diff against the base. Tests are mapped from those paths the way its Step 4
maps them. Named files and examples only, never a directory and never the whole
suite, whether or not the project declares a ship gate.

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

## Step 5 · `arm` — Leave the PR armed for the gate to release

GitHub keeps auto-merge on across a push from someone with write access. So a PR
armed at hand-off is still armed, and the gate's green is what merges it. Read
`autoMergeRequest` again and settle it **before** the gate runs. Arming ahead of
the gate is safe because the gate's status is required.

- **Armed** → leave it.
- **Not armed, and it shouldn't be** → leave it and say which reason applies:
  - the project's `## Auto-merge` says `off`, or `gh api repos/{owner}/{repo}
    --jq .allow_auto_merge` is `false`;
  - the PR is a draft;
  - it carries `kit-hold`, in the project's spelling (`kit:project-rules`
    *Labels*), and the project declares no `## Hold check` of `required`.
- **Not armed otherwise** → ask whether to arm it. An operator who disabled
  auto-merge made a decision that stands (`kit:ticket-loop` `hand-off` step 5),
  and nothing on the PR says whether the disable was deliberate. On yes,
  `gh pr merge <n> --auto --<method>`, with the method from `## Auto-merge`, else
  the project's rules in their own words, else `squash`.

## Step 6 · `gate` — Run the ship gate once, on the pushed head

Look for a `## Ship gate` section in the project's rules (`kit:project-rules`).

**Absent → skip this step.** CI is the gate, and nothing here runs the full
suite.

**Present → first confirm the head.** `git -C <worktree> rev-parse HEAD` must
equal the PR's `headRefOid` as GitHub reports it now. If it doesn't, the push
didn't land or someone pushed after it, and a gate run now would attest the
wrong commit. Say which and stop.

Then run its `run:` command once, from `<worktree>`. Commit nothing and push
nothing during or after it. A push after the gate leaves the PR on a head the gate
never saw.

- **Zero** → the status is posted, and an armed PR merges on it.
- **Non-zero** → show the person the failing output. The PR stays unmerged
  because the gate's status is required, so leave auto-merge as Step 5 left it.
  Disarming would only make the person re-arm it once the fix is pushed. The fix
  is a new push followed by one more gate run, which is this command again from
  Step 3.

## Step 7 · `report` — Say what happened

Release the lease first: `git worktree unlock <worktree>`. Release it however
the command ends, including a stop at Step 3 or Step 6, because a lease nobody
releases holds the worktree against every sweep until it expires.

Then read the PR once: `gh pr view <n> --json state,autoMergeRequest,statusCheckRollup`.
Report what you find, not what you did:

> "PR #<N>: resolved <k> conflicted files (<which were decided by you>), checked
> <what ran>, and pushed <short SHA>. <Ship gate passed | Ship gate failed — the
> output is above, and the PR stays unmerged | No ship gate, so CI decides>.
> Auto-merge <reads on | reads off — <why>>. <Any failing check the rollup names.>"

Leave the worktree in place. Once the PR merges, the next `/kit:ship-ticket` or
`/kit:worktree-gc` reclaims it.
