---
name: worktree-conventions
description: Resolve where a project's git worktrees live and how they are created, provisioned, served, and removed — by delegating to the project's own command when it has one, and falling back to a built-in layout when it doesn't. Use whenever a command needs to make, find, or remove a worktree.
license: MIT — Copyright (c) 2026 Ron Ranauro, https://github.com/rranauro/claude-kit
---

# Worktree Conventions

Every command in this suite operates on a worktree, and none of them should
decide where worktrees go. Many projects already own that: a `just` recipe, a
`make` target, a setup script that creates the worktree *and* installs deps,
links a dev proxy, and writes a local config file.

When one exists, **delegate to it and detect what it did.** Never reimplement it,
and never place a worktree somewhere the project didn't choose.

## Step 1 — Read the convention

Look for a `## Worktrees` section in the project's rules, found as
`kit:project-rules` says:

```markdown
## Worktrees
- create: `just worktree <branch>`
- remove: `just del-worktree <branch>`
- provisions: yes
- server: `bin/dev`
- url: `http://<branch>.localhost`
```

- **create** — makes the worktree for a branch. May do far more than
  `git worktree add`.
- **remove** — tears one down. Often does more than `git worktree remove`; a
  recipe that also unlinks a dev proxy is the common case, and skipping it
  leaves a dangling link nothing will ever clean up. **The declared line is the
  call:** `<branch>` and `<path>` are replaced by the worktree's branch and
  absolute path, and nothing else is passed. A line naming neither placeholder
  gets the branch appended as its one argument. A project wanting the path
  writes `<path>`. Shell quotes group an argument, but the line is never run
  through a shell, so pipes, `&&` and variables are passed through as literal text.
- **provisions** — `yes` means create also installs dependencies and wires
  runtime files. Then `kit:start-ticket`'s `wire-worktree` must be **skipped
  entirely**, not merged with — re-symlinking on top of a real install is how
  you get a `node_modules` symlink pointing at a directory the project just
  populated for real.
- **server** — boots the app for one worktree. Called exactly as `remove` is —
  the same placeholders, the same quoting, never a shell — except that a line
  naming neither placeholder gets nothing appended, since it runs from inside
  the worktree. *The worktree's server* below says when it runs.
- **url** — where that server answers, with `<branch>` and `<path>` substituted
  and nothing else. The kit never derives a port or a hostname, so a port per
  worktree and a subdomain proxy are both just a URL the project writes down.

If there's no such section, check whether the project obviously has one anyway —
a `worktree` recipe in a `justfile`, a `make worktree` target, a script named for
it. If you find one, **ask** before using it, and offer to record the answer as
`kit:project-rules` *Recording a setting* allows, so the next session doesn't
re-derive it.

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
`kit:worktree-reclaim`, `/kit:polish-ticket`, `/kit:walkthrough`, and `/kit:ship-ticket` locate
one without knowing the layout.

**Verify the base.** A project's create command commonly cuts the branch from
`HEAD` — whatever you happened to be sitting on — while this suite bases work on
`origin/<base>`, resolved as `kit:project-rules` *The base branch* says. After
delegating:

```
git fetch origin <base>
git -C <worktree> merge-base --is-ancestor origin/<base> HEAD || echo behind
```

If the branch is behind, say so and offer to rebase onto `origin/<base>`. Don't
rebase silently: the project may cut from `HEAD` deliberately for stacked work.

## Step 3 — Remove by delegating

If the convention names a **remove** command, use it, and do not follow it with a
raw `git worktree remove` — it already ran one. What it adds around that (proxy
links, generated config, registered subdomains) is precisely the part you cannot
reconstruct, which is why it exists.

**A non-zero exit is a refusal, and it stands.** The project's teardown is
checking something the kit cannot see — migrations still applied to a shared
database, a process still running. Leave the worktree and its branch in place,
even where the directory is already gone, and report the command's own output:
that output is the only record of why it refused.

If it names no remove command, `kit:worktree-reclaim` removes it.

**A project with a worktree server stops it here.** Its `remove` is the only
teardown the kit runs, so a `remove` that leaves the server running leaks one
process per reclaimed worktree, each still bound to its URL.

## Step 4 — Fallback layout

With no project convention, this suite owns the layout:

```
.claude/worktrees/<branch-name>/
```

Inside the repo, never as a sibling of the main checkout. Create with
`git worktree add .claude/worktrees/<branch> -b <branch> origin/<base>`, then run
`kit:start-ticket`'s `wire-worktree` to link the gitignored files the app needs to
boot.

## The worktree's server

A project declaring `server` and `url` has a server that lives as long as its
worktree: an attended pass that creates the worktree boots it, and any later pass
that needs it makes sure it answers. It stops when the project's `remove` runs.

**Only an attended pass boots.** A pass handed `unattended`, and every runner
session, boots nothing, so a process nobody watches is never left running on a
machine nobody is at. Whether a server boots turns on the declaration and the
mode alone. No label enters into it — `kit-hold` included.

**No `remove`, no boot.** The kit never stops a server itself: the project's
`remove` owns teardown, and reclaim runs that and nothing else. A project that
declares `server` but no `remove` has declared a process nothing could ever
stop, so boot nothing and say:

> "This project declares a worktree server but no `remove`, so nothing would
> stop it. Add a `remove` line to `## Worktrees` that stops the server and
> removes the worktree."

A project declaring `server` without `url` gets the same treatment: with no URL
there is nothing to ask whether it already answers. Declaring neither line
changes nothing anywhere.

**Make it answer, after wiring.** Run this once the worktree's gitignored files
are linked, since an app missing its credentials boots into an error:

```
${CLAUDE_PLUGIN_ROOT}/scripts/worktree-server.sh --server '<server line>' --url '<url line>' --branch <branch> --path <worktree>
```

It asks the URL first and boots only when nothing answers, so calling it on a
worktree whose server is up is free and never starts a second one. That is
what makes "answers again after a sleep, a reboot or a crash" safe to ask for
every time a pass needs the server. It prints one record:

- `answering` / `booted` — the server is up at the URL it names. Say which.
- `not-answering` — it booted, but nothing answered in time. Say so with the
  log path it names; the worktree is still usable, and the server may only be
  slow.
- `not-started` — the line did not parse or the command did not run. Quote the
  reason.

None of these stops the pass. A server that does not come up is the person's to
look at, and the work in the worktree does not depend on it.

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

Either way, `chmod -R u+rwX <path>` before `rm -rf`: an app booted in the worktree
leaves cache files whose writer marked them read-only, and `rm -rf` aborts
partway on those, replacing a big husk with a smaller one. `u+rwX` rather than
`u+w` — a directory left non-traversable cannot be descended into to delete what
is under it, so the sweep fails on the directory itself. `X` adds execute to
directories only, never to files.
