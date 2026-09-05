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

## What this means for garbage collection

Declaring the layout also narrows what a reclaim pass will sweep — whether it was
asked for with `/kit:worktree-gc` or ran on its own at the top of
`/kit:ship-ticket`, which is where worktrees get reclaimed without anyone
remembering to. Under the built-in layout the directory holds nothing but
worktrees, so anything git no longer names is garbage. Under a sibling layout like `../<repo>-<branch>`, the
same diff would propose deleting unrelated repositories that happen to share the
parent — so gc falls back to sweeping only paths it removed in that run, and says
so.
