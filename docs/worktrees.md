# Worktree layout

By default worktrees go under `.claude/worktrees/<branch>` inside the repo, and
`kit:start-ticket` links the gitignored files the app needs to boot.

## Delegating to your project's own command

If your project already owns this — a `just` recipe, a `make` target, a setup
script that creates the worktree *and* installs deps and links a dev proxy —
declare it in `CLAUDE.md` and the commands delegate instead:

```markdown
## Worktrees
- create: `just worktree <branch>`
- remove: `just del-worktree <branch>`
- provisions: yes
```

`provisions: yes` means `kit:start-ticket` skips its own wiring rather than
symlinking on top of a real install. The path is never configured — it's read
back from `git worktree list --porcelain` after your command runs, so a layout
this suite has never seen still works.

Declaring `remove` matters more than it looks. A recipe that unlinks a dev proxy
or drops a registered subdomain is doing something no generic
`git worktree remove` can reconstruct, and skipping it leaks that resource on
every cleanup.

## Ownership while a pass is working

Passes run concurrently by design — `plugins/kit/scripts/ship-startable.sh` exists
to do exactly that — and every one of them sweeps before it selects. A worktree
another pass created moments ago holds no uncommitted work between commits, so
freeness alone would hand it to the sweep while its owner is still writing in it.

So a ship pass takes a **lease**: `kit:start-ticket` locks the worktree with the
reason `kit:ship #<issue> since <timestamp>`, and `kit:ticket-loop` unlocks it
when the pass ends, whether that is an open PR or a park. Reclaim already holds a
locked worktree, so nothing coordinates and no operator has to serialise anything.

The timestamp is what keeps a killed pass from owning a worktree forever:
`worktree-reclaim.sh` treats a `kit:ship` lease older than twelve hours as
expired. That window is scoped to the kit's own wording — a lock you write by
hand still holds until you unlock it.

**Twelve hours of the machine being awake, though, not twelve hours on the
wall.** A pass's own waits are bounded in process time — `await-reviews.sh` caps
its review round at 900 seconds — so a pass can only ever be minutes from its
next act. Wall-clock age therefore measures how long the machine slept, which is
not a fact about the pass at all: #183 was a pass six minutes from returning
whose lease read as thirteen hours abandoned, reclaimed while it waited, leaving
a draft PR nobody signed off and no record of why.

So the lease also carries a reading of a clock that stops with the machine, and
the boot it was read against. A sleeping pass spends none of its window; a pass
that has burned twelve awake hours without acting has stopped, whatever its lock
says. A reading from a boot that is gone is expired outright — a reboot kills
every pass, so a lease that did not survive one is dead rather than merely old,
and that case is now reclaimed on the next sweep instead of waiting out a window
it was never really inside.

What this accepts is the pass whose session died while the machine stayed up: it
loses its lease after twelve awake hours, and `kit:ticket-loop` `hand-off` is
what makes that survivable, because a pass returning to a worktree that is gone
says so rather than carrying on.

The lease ends where the pass does, which is the close of the review round —
`hand-off` addresses both reviews, judges the diff's shape and runs the
project's ship gate in the worktree before it unlocks. For a PR that has to be
walked the worktree is needed after that too — `/kit:walkthrough` runs in it,
and keeps its position on disk precisely so a walk can be resumed days later. `kit-hold` is what covers
that stretch: reclaim holds the worktree of any open PR carrying it. Nothing is
left to take a second lock, and the hold ends when the label or the PR does.

## What this means for garbage collection

Declaring the layout also narrows what a reclaim pass will sweep — whether it was
asked for with `/kit:worktree-gc` or ran on its own at the top of
`/kit:ship-ticket`, which is where worktrees get reclaimed without anyone
remembering to. Under the built-in layout the directory holds nothing but
worktrees, so anything git no longer names is garbage. Under a sibling layout like `../<repo>-<branch>`, the
same diff would propose deleting unrelated repositories that happen to share the
parent — so gc falls back to sweeping only paths it removed in that run, and says
so.
