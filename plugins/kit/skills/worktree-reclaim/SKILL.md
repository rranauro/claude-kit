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
throwaway repository. `tests/worktree-reclaim.sh` is where the behaviour is
pinned. What this skill owns is the judgement the script cannot make and the
report a person reads.

## Two decisions, two tests

**Reclaiming the directory and deleting the branch are separate**, and conflating
them is what made the old commands frightening.

A worktree is a checkout. Removing one loses nothing a branch still holds, and
restoring it is a single `git worktree add`. That is what makes reclaiming safe
unattended, with no age threshold and no prompt — and it is why a branch that
never had a pull request is no longer the one category that cannot clear itself.
Its directory goes; its branch is a separate question.

So **freeness is about work, not about occupancy.** Uncommitted changes hold a
worktree, and so does a `git worktree lock`, which is somebody saying out loud
that they are in there. A shell or an editor sitting in the directory does not:
what it would lose is a checkout that comes back in one command, and treating it
as a hold would defer every sweep behind a terminal somebody forgot to close.
Lock the worktree if you need it kept.

**A ship pass locks the worktree it is working in**, with the reason
`kit:ship #<issue> since <timestamp>`. The script reads that wording as a
**lease** and expires it, so a pass that was killed and cannot unlock stops
holding the worktree — `docs/worktrees.md` says why, and the script's own
`KIT_LEASE_HOURS` is the window. Every other lock holds until somebody unlocks
it.

**A branch is deleted only where GitHub accounts for its tip** — the local tip
commit is itself associated with a merged or closed PR, or, for a branch that
never had a PR, the tip is present on a remote ref. Where the answer is no,
including when GitHub could not be reached, the branch stays and is reported.
`docs/adr/0002-branch-deletion-is-gated-on-remote-accounting.md` carries the
argument and the alternatives it beat; do not re-derive it here.

Any other caller that deletes a branch asks the same way, through
`worktree-reclaim.sh --account <branch>`.

## Phases

`layout` → `inventory` → `verdicts` → `act` → `report`.

### 1 · `layout` — who owns worktrees here

Run `kit:worktree-conventions`. Two of its answers become flags:

- **A remove command**, passed as `--remove-cmd`. It is invoked as
  `<cmd> <branch> <path>` and **replaces** `git worktree remove` rather than
  preceding it — Step 3 of that skill says why.
- **Its sweep rule**, which decides whether you may name a `--worktree-root`.
  Pass one only for a directory holding nothing but worktrees this suite placed;
  the root is the assertion, and without it the script lists no directory at all.
  Read the rule there rather than guessing — it is the difference between
  sweeping husks and proposing to delete somebody else's repository.

**Per-directory daemons are not this skill's business.** Which daemons a checkout
runs is a property of the project, and the kit cannot verify a list it holds on
the project's behalf. A project that needs a language server or test daemon
stopped does it in its own remove command.

### 2 · `inventory` and 3 · `verdicts` — run the script

```
scripts/worktree-reclaim.sh --repo <main-checkout> [--target <branch|path>] \
  [--worktree-root <dir>] [--remove-cmd <cmd>]
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

**Unattended, pass `--act`** and do not ask. The script never reads stdin.

### 5 · `report`

Say what happened, from the records rather than from what you expected:

- `removed` / `swept` — directories reclaimed, and husks cleared.
- `branch-deleted` — with the PR or remote ref that accounted for the tip.
- `branch-kept` — **name every one, with its reason.** A branch holding commits
  GitHub never received is the outcome this whole design exists to produce, and
  it is worthless if nobody is told. These accumulate silently otherwise.
- `held` — with the reason. A `kit:ship` lease here is a pass still working;
  leave it and say which ticket owns it.
- `orphan` — husks git had stopped tracking.

If no `--worktree-root` was passed, say that husks were not swept and why, so
nobody reads a clean report as "there are none".
