---
model: sonnet
---

Sweep this repo's worktrees — remove the ones whose branches are merged, and delete the husks git has stopped tracking.

**Arguments:** none.

`/kit:cleanup-worktree` handles one ticket at the moment it merges. This is the
periodic pass for everything that didn't go through it: worktrees abandoned
mid-ticket, ones whose PR merged while you were elsewhere, and directories left
behind by a previous cleanup. Run it from the main checkout.

---

## Step 1 · `layout` — Establish who owns worktrees here

Run the `kit:worktree-conventions` skill **before touching anything.** Two answers
change how the rest of this command behaves, and one of them is a safety
constraint, not a preference:

- **Does the project have a remove command?** If so, `remove` delegates to it.
  Skipping it strands whatever it cleans up alongside the worktree — a dev-proxy
  link, a registered subdomain, generated config.
- **Who chose the layout?** This decides what `orphans` is allowed to do. Read
  the skill's sweep rule and follow it exactly; the two cases are not
  interchangeable.

---

## Step 2 · `inventory` — Capture the list up front

```
git worktree list --porcelain
```

**Keep this output.** It is the authoritative record of which paths are
worktrees, and `orphans` needs it as it was *before* any removal — afterwards,
the paths you removed are indistinguishable from paths that were never
worktrees at all.

Ignore the main worktree in everything that follows.

---

## Step 3 · `find-merged` — Check against the remote, now

```
git fetch origin main
git branch --merged origin/main
```

**Fetch first, every time.** A branch's merge state changes on GitHub without
anything happening locally, and a stale `origin/main` reports a merged branch as
unmerged — which reads as "still in progress" and keeps a dead worktree alive
for another week. The live answer is the only one worth acting on.

A squash-merged branch will **not** appear in `--merged`: squashing collapses its
commits into one new commit, so the local branch is not an ancestor of `main`.
For any worktree the list doesn't cover, check its PR directly —
`gh pr list --head <branch> --state merged --json number,mergedAt` — and treat a
merged PR as authoritative over git's ancestry answer.

---

## Step 4 · `present` — Show the whole picture, then ask

Show two tables: worktrees eligible for removal, and worktrees whose branches are
still open. The second table is not filler — it's how the user notices they left
something half-finished.

```
Path                       Branch                  Status
<path>/123-fix-search      123-fix-search          merged (squash, #124)
<path>/456-update-exports  456-update-exports      merged
<path>/789-new-feature     789-new-feature         open PR #791
<path>/802-spike           802-spike               no PR
```

Then ask: remove all the merged ones, or choose individually? **Never delete
without confirmation, even when everything is merged.**

---

## Step 5 · `remove` — Per worktree

**If the project has a remove command, run it** and let it do the whole job.
Don't follow it with a raw `git worktree remove`; it already ran one.

Otherwise:

```
git worktree remove <path>
git branch -D <branch>
```

- `git worktree remove`, not `rm -rf` — git's bookkeeping has to be updated too.
- `-D` on the branch, not `-d`. `present` already established the branch is
  merged upstream, and `-d` refuses squash-merged branches on ancestry grounds
  that carry no information once the PR is confirmed merged.
- If `remove` fails because the worktree is dirty, **report it and skip.** Don't
  force. Uncommitted work in an abandoned worktree is exactly the thing this
  command must not eat.
- Before removing, stop any per-directory daemon bound to that path — language
  servers, watchers, test daemons, RuboCop's server mode. They orphan themselves
  when the directory disappears underneath them and accumulate across tickets.
  No-ops when nothing is running, so don't prompt.

---

## Step 6 · `prune` — Clear git's admin files

```
git worktree prune
```

---

## Step 7 · `orphans` — Sweep the husks

**Do this even when Steps 3–6 found nothing.** Orphans accumulate from *past*
runs and from manual `rm -rf`s; the sweep is as much the point of this command
as the merged check is.

`git worktree remove` deletes tracked files only. Untracked paths — build output,
caches, logs, dependency directories — survive it, and `git worktree prune`
cleans git's admin files without ever touching a directory. So removal routinely
leaves a husk that nothing notices.

**How you find them depends entirely on who owns the layout. Take exactly one of
these branches.**

### This suite owns the layout (`.claude/worktrees/`)

That directory holds nothing but worktrees this suite created, which is what
licenses a directory diff:

```
ls -1 .claude/worktrees/
git worktree list --porcelain
```

Anything listed by `ls` that git does not name is an orphan.

**Only ever `rm -rf` inside `.claude/worktrees/`.** That constraint is the whole
basis for acting on the diff. Never extend the sweep upward.

### The project owns the layout

**Do not list the worktree directory. Do not diff it.** A project layout is
frequently a sibling of the main checkout — `../<repo>-<branch>` and the like —
which puts worktrees in the same parent as unrelated repositories, personal
projects, and whatever else lives there. A directory diff in that parent
proposes deleting things that were never worktrees, and the proposal will look
entirely plausible.

The only safe source is `inventory`, captured in Step 2 before any removal: a
path that git listed then, that Step 5 removed, and that still exists on disk.
That set is small, exact, and cannot include a directory this command never
touched.

If the project has a remove command, expect this set to be empty — cleaning up
after itself is what that command is for. Say so rather than going looking.

### Either branch — deleting one

Show each candidate with its size (`du -sh`), ask, and on approval:

```
chmod -R u+rwX <path> 2>/dev/null; rm -rf <path>
```

The `chmod` is not optional — an app booted in the worktree leaves cache files
whose writer set them read-only, and `rm -rf` aborts partway on those, leaving a
smaller husk in place of the big one. `u+rwX`, not `u+w`: a directory that is not
traversable cannot be descended into to delete what is under it, so the sweep
fails on the directory rather than on the files inside it. `X` adds execute to
directories only.

---

## Step 8 · `report`

Worktrees removed, branches deleted, orphans swept with reclaimed size, and
anything skipped — with the reason. A skipped dirty worktree is the line the
user most needs to see.

If Step 7 took the project-owned branch, say that the sweep was limited to paths
this run removed. A user who believes every husk was found, when only some were,
is worse off than one who knows where to look.
