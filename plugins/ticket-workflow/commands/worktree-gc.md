---
model: sonnet
---

Sweep `.claude/worktrees/` — remove worktrees whose branches are merged, and delete the husks git has stopped tracking.

**Arguments:** none.

`/cleanup-worktree` handles one ticket at the moment it merges. This is the
periodic pass for everything that didn't go through it: worktrees abandoned
mid-ticket, ones whose PR merged while you were elsewhere, and directories left
behind by a previous cleanup. Run it from the main checkout.

`.claude/worktrees/` holds nothing but worktrees. That is what makes `orphans`
below safe — anything in that directory git doesn't name is garbage.

---

## Step 1 · `inventory` — List both sides

```
git worktree list
ls -1 .claude/worktrees/ 2>/dev/null
```

Keep both outputs. `orphans` diffs them, and it needs the listing from *before*
anything is removed.

Ignore the main worktree in everything that follows.

---

## Step 2 · `find-merged` — Check against the remote, now

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

## Step 3 · `present` — Show the whole picture, then ask

Show two tables: worktrees eligible for removal, and worktrees whose branches are
still open. The second table is not filler — it's how the user notices they left
something half-finished.

```
Path                                  Branch                  Status
.claude/worktrees/123-fix-search      123-fix-search          merged (squash, #124)
.claude/worktrees/456-update-exports  456-update-exports      merged
.claude/worktrees/789-new-feature     789-new-feature         open PR #791
.claude/worktrees/802-spike           802-spike               no PR
```

Then ask: remove all the merged ones, or choose individually? **Never delete
without confirmation, even when everything is merged.**

---

## Step 4 · `remove` — Per worktree

```
git worktree remove .claude/worktrees/<name>
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

## Step 5 · `prune` — Clear git's admin files

```
git worktree prune
```

---

## Step 6 · `orphans` — Sweep the husks

**Do this even when Steps 2–5 found nothing.** Orphans accumulate from *past*
runs and from manual `rm -rf`s; the sweep is as much the point of this command
as the merged check is.

`git worktree remove` deletes tracked files only. Untracked paths — build output,
caches, logs, `node_modules` — survive it, and `git worktree prune` cleans git's
admin files without ever touching a directory. So removal routinely leaves a husk
that nothing notices.

Re-list both sides and diff them:

```
git worktree list
ls -1 .claude/worktrees/
```

Any directory in `.claude/worktrees/` that `git worktree list` does not name is
an orphan. Show each with its size (`du -sh`), ask, and on approval:

```
chmod -R u+w .claude/worktrees/<orphan> 2>/dev/null; rm -rf .claude/worktrees/<orphan>
```

The `chmod` is not optional — an app booted in the worktree leaves cache files
whose writer set them read-only, and `rm -rf` fails partway through on those,
leaving a smaller husk in place of the big one.

**Only ever `rm -rf` inside `.claude/worktrees/`.** That constraint is what makes
the diff safe to act on. Never extend the sweep upward.

---

## Step 7 · `report`

Worktrees removed, branches deleted, orphans swept with reclaimed size, and
anything skipped — with the reason. A skipped dirty worktree is the line the
user most needs to see.
