---
name: worktree-reclaim
description: Reclaim git worktrees and delete their branches safely — one named target or a sweep, attended or unattended. Use when a ticket has merged, when worktrees have accumulated, or when another command needs a worktree torn down.
---

# Worktree Reclaim

Reclaiming a worktree at one cardinality and at many is the same act, so it is
one skill. An optional target selects a single worktree; no argument sweeps.

**The mechanical half is not written here.** `scripts/worktree-reclaim.sh` in
this plugin does the inventory, the verdicts, and the acting, because those are
deterministic and a paragraph of instructions cannot be asserted against a
throwaway repository. `tests/worktree-reclaim.sh` in this repo is where the
behaviour is pinned. What this skill owns is the judgement the script cannot
make and the report a person reads.

## Two decisions, two tests

**Reclaiming the directory and deleting the branch are separate**, and conflating
them is what made the old commands frightening.

A worktree is a checkout. Removing one loses nothing a branch still holds, and
restoring it is a single `git worktree add`. That is what makes reclaiming safe
unattended, with no age threshold and no prompt — and it is why a branch that
never had a pull request is no longer the one category that cannot clear itself.
Its directory goes; its branch is a separate question.

**A branch is deleted only where GitHub accounts for its tip.** Not because the
safe test is hard, but because the old code never asked. A `git branch -d`
refusal has two causes that are identical from the local side:

- a squash-merge, whose original commits are unreachable from every remote ref
  because squashing made a new commit, and
- work that was committed and never pushed.

`git rev-list <branch> --not --remotes` cannot separate them either, for the same
reason. Only the side that received the push can. So the script asks: a merged or
closed PR whose `headRefOid` equals the local tip means GitHub received exactly
this tip. A local tip ahead of it means commits GitHub has never seen. A branch
with no PR at all falls back to whether its tip is on a remote ref. Where the
answer is no — including when GitHub could not be reached — the branch stays and
is reported.

Any other caller that deletes a branch asks the same way, through
`worktree-reclaim.sh --account <branch>`. One implementation of the test; a copy
per caller is the shape that produced the defect.

## Phases

`layout` → `inventory` → `verdicts` → `act` → `report`. A target skips
`inventory`. Attended stops after `verdicts` and asks; unattended continues into
`act`.

### 1 · `layout` — who owns worktrees here

Run `kit:worktree-conventions`. Two of its answers change what happens next, and
one is a safety constraint rather than a preference:

- **A remove command.** If the project has one, pass it as `--remove-cmd`. It is
  invoked as `<cmd> <branch> <path>` in place of `git worktree remove`, never
  after it. What it does around the removal — unlinking a dev proxy, dropping a
  registered subdomain, deleting generated config — is precisely the part that
  cannot be reconstructed afterwards.
- **Who chose the layout.** Pass `--layout owned` with `--worktree-root` only for
  this suite's own `.claude/worktrees/`. Everything else is `--layout project`,
  and the script then refuses to list a directory it did not place. A project
  layout is frequently a sibling of the main checkout, which puts worktrees in
  the same parent as unrelated repositories; a directory diff there proposes
  deleting somebody else's work, and the proposal looks entirely plausible.

**Per-directory daemons are not this skill's business.** Which daemons a checkout
runs is a property of the project, and the kit cannot verify a list it holds on
the project's behalf. A project that needs a language server or test daemon
stopped does it in its own remove command — the seam `kit:worktree-conventions`
already defines.

### 2 · `inventory` and 3 · `verdicts` — run the script

```
scripts/worktree-reclaim.sh --repo <main-checkout> [--target <branch|path>] \
  --layout <owned|project> [--worktree-root <dir>] [--remove-cmd <cmd>]
```

Without `--act` it changes nothing and prints one `verdict` record per worktree:

```
verdict<TAB>branch<TAB>path<TAB><verdict><TAB>free-reason<TAB>branch-reason
```

The verdict is one of `reclaim`, `reclaim-keep-branch`, or `hold`, and the two
reasons say how each half was decided. Read them; they are what the report is
made of.

### 4 · `act`

**Attended, stop here and ask.** Show the verdicts as a table and ask whether to
proceed — all of them, or a chosen subset. A `hold` line is not filler: it is how
someone notices they left work in a worktree they had forgotten about.

**Unattended, pass `--act`** and do not ask. The script never reads stdin. It
removes each free worktree, sweeps whatever survives the removal, deletes only
accounted branches, and prunes git's bookkeeping.

Deleting a branch unattended is a genuine widening of what the kit does without
supervision. It is safe here because the test is a positive check against the
remote rather than an inference from a local refusal — and unsafe the moment
anyone reintroduces the inference.

### 5 · `report`

Say what happened, from the records rather than from what you expected:

- `removed` / `swept` — directories reclaimed, and husks cleared.
- `branch-deleted` — with the PR or remote ref that accounted for the tip.
- `branch-kept` — **name every one, with its reason.** A branch holding commits
  GitHub never received is the outcome this whole design exists to produce, and
  it is worthless if nobody is told. These accumulate silently otherwise.
- `held` — with the reason. A worktree someone is working in, or one locked.
- `orphan` — husks git had stopped tracking.

Under `--layout project`, say that the sweep was limited to paths this run
removed. Someone who believes every husk was found, when only some were, is worse
off than someone who knows where to look.
