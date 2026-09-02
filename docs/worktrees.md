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

## What this means for garbage collection

Declaring the layout also narrows what `/kit:worktree-gc` will sweep. Under the
built-in layout the directory holds nothing but worktrees, so anything git no
longer names is garbage. Under a sibling layout like `../<repo>-<branch>`, the
same diff would propose deleting unrelated repositories that happen to share the
parent — so gc falls back to sweeping only paths it removed in that run, and says
so.
