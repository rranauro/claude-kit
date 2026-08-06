---
name: worktree-conventions
description: Resolve where a project's git worktrees live and how they are created, provisioned, and removed — by delegating to the project's own command when it has one, and falling back to a built-in layout when it doesn't. Use whenever a command needs to make, find, or remove a worktree.
---

# Worktree Conventions

Every command in this suite operates on a worktree, and none of them should
decide where worktrees go. Many projects already own that: a `just` recipe, a
`make` target, a setup script that creates the worktree *and* installs deps,
links a dev proxy, and writes a local config file.

When one exists, **delegate to it and detect what it did.** Never reimplement it,
and never place a worktree somewhere the project didn't choose.

## Step 1 — Read the convention

Look for a `## Worktrees` section in the project's `CLAUDE.md` (root first, then
any that applies to the path you're working in):

```markdown
## Worktrees
- create: `just worktree <branch>`
- remove: `just del-worktree <branch>`
- provisions: yes
```

- **create** — makes the worktree for a branch. May do far more than
  `git worktree add`.
- **remove** — tears one down. Often does more than `git worktree remove`; a
  recipe that also unlinks a dev proxy is the common case, and skipping it
  leaves a dangling link nothing will ever clean up.
- **provisions** — `yes` means create also installs dependencies and wires
  runtime files. Then `/kit:start-ticket`'s `wire-worktree` must be **skipped
  entirely**, not merged with — re-symlinking on top of a real install is how
  you get a `node_modules` symlink pointing at a directory the project just
  populated for real.

If there's no such section, check whether the project obviously has one anyway —
a `worktree` recipe in a `justfile`, a `make worktree` target, a script named for
it. If you find one, **ask** before using it, and offer to record the answer in
`CLAUDE.md` so the next session doesn't re-derive it.

Absent both, use the fallback in Step 4.

## Step 2 — Create by delegating, then detect the path

Run the project's create command. Then ask git where the worktree landed —
**never assume, and never parse the command's output**:

```
git worktree list --porcelain
```

Entries are `worktree <abs-path>` / `HEAD <sha>` / `branch refs/heads/<name>`
blocks. Find the block whose branch matches and take its path. That absolute
path is what every later Read/Edit/Write targets.

The same lookup finds an *existing* worktree for a branch, which is how
`/kit:cleanup-worktree`, `/kit:polish-ticket`, `/kit:walkthrough`, and `/kit:ship-ticket` locate
one without knowing the layout.

**Verify the base.** A project's create command commonly cuts the branch from
`HEAD` — whatever you happened to be sitting on — while this suite bases work on
`origin/main`. After delegating:

```
git fetch origin main
git -C <worktree> merge-base --is-ancestor origin/main HEAD || echo behind
```

If the branch is behind, say so and offer to rebase onto `origin/main`. Don't
rebase silently: the project may cut from `HEAD` deliberately for stacked work.

## Step 3 — Remove by delegating

If the convention names a **remove** command, use it, and do not follow it with a
raw `git worktree remove` — it already ran one. What it adds around that (proxy
links, generated config, registered subdomains) is precisely the part you cannot
reconstruct, which is why it exists.

If it names no remove command, remove it yourself per `/kit:cleanup-worktree`.

## Step 4 — Fallback layout

With no project convention, this suite owns the layout:

```
.claude/worktrees/<branch-name>/
```

Inside the repo, never as a sibling of the main checkout. Create with
`git worktree add .claude/worktrees/<branch> -b <branch> origin/main`, then run
`/kit:start-ticket`'s `wire-worktree` to link the gitignored files the app needs to
boot.

## The sweep rule

`git worktree remove` deletes tracked files only. Untracked paths — caches,
logs, build output — survive it, and `git worktree prune` never touches a
directory. So husks accumulate, and something has to delete them.

**What makes deleting one safe depends entirely on the layout, and the two cases
are not interchangeable:**

- **Fallback layout (`.claude/worktrees/`)** — the directory holds nothing but
  worktrees, and this suite created all of them. A directory there that
  `git worktree list` doesn't name is garbage by construction. Listing the
  directory and deleting the difference is safe.

- **A project-defined layout** — assume nothing. Sibling layouts like
  `../<repo>-<branch>` put worktrees in the same parent as unrelated checkouts,
  and a directory diff there proposes deleting other people's repositories.
  **Never list a directory you did not place.** Only ever remove a path that
  `git worktree list` named *before* the removal, captured up front. If the
  project has a remove command, this doesn't arise — let it clean up.

Either way, `chmod -R u+w <path>` before `rm -rf`: an app booted in the worktree
leaves cache files whose writer marked them read-only, and `rm -rf` aborts
partway on those, replacing a big husk with a smaller one.
