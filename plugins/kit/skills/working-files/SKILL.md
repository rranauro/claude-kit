---
name: working-files
description: Resolve where the kit keeps a project's working files — the plan cache, the PR scratch notes, the glossary and the ADR directory — from the project's `## Working files` section, and keep a local one out of git without touching a tracked `.gitignore`. Use whenever a command or skill builds one of those paths, before it reads, writes or excludes it.
license: MIT — Copyright (c) 2026 Ron Ranauro, https://github.com/rranauro/claude-kit
---

# Working Files

Four places the kit reads and writes sit at the repository root by default. A
monorepo that forbids new root entries has to be able to move them, and every
reader has to agree on where they went — a plan cached in one directory and
looked for in another is a plan nobody finds offline. So no command or skill
builds one of these paths itself. It asks here.

**This is shared mechanism, not an entry point.** It owns the section's keys and
the exclude rule; what lives in each location belongs to whoever writes it.

## The section

Look for a `## Working files` section in the project's rules, found as
`kit:project-rules` says:

```markdown
## Working files
- plans: `tools/kit/plans`
- tickets: `tools/kit/tickets`
- glossary: `docs/CONTEXT.md`
- adr: `docs/decisions`
```

| Key | What lives there | Default | Local or tracked |
|---|---|---|---|
| `plans` | The cache `kit:ticket-artifacts` mirrors, and the reports and pages written beside it | `plans/` | Local |
| `tickets` | The PR scratch notes `/kit:new-pull-request` writes | `tickets/` | Local |
| `glossary` | The single-context glossary `kit:domain-modeling` keeps | `CONTEXT.md` | Tracked |
| `adr` | The ADR directory `kit:domain-modeling` keeps | `docs/adr/` | Tracked |

**Every key is optional.** An absent key is its default, and so is every key when
the section is absent — a project that names nothing sees the toplevel layout it
always had.

**A path is relative to the repository root, whichever file declared it.** A
sub-project's `CLAUDE.md` writing `plans: rx/tmp/plans` means the same directory
the toplevel one would, so a line copied between files cannot silently move. An
absolute path is allowed and means outside the repository — it belongs in
`CLAUDE.local.md`, since no other developer has that directory.

**Resolve the local ones against the main checkout** — the first `worktree` line
of `git worktree list --porcelain` — never a worktree. A cache in a worktree dies
with the ticket. `kit:start-ticket` links the `plans` location into each worktree
at the same relative path, so a read from inside one finds the same files. The
tracked ones resolve against whatever checkout the caller is writing in, because
their edits ship in that checkout's PR.

## Keeping a local one out of git

A local location must not show up as untracked work. Before the first write to
one:

```
git -C <main checkout> check-ignore -q <relative path> \
  || echo "/<relative path>" >> "$(git -C <main checkout> rev-parse --git-common-dir)/info/exclude"
```

`mkdir -p "$(dirname <exclude file>)"` first if `info/` is missing.

**Never edit a tracked `.gitignore` to do it.** These writes run from the main
checkout, usually on the default branch, so an added line is a tracked change no
ticket owns — it ships with whoever's PR picks it up next, or with nobody's.
`info/exclude` under the common directory is per-clone and covers every worktree
of it; `scripts/observe.sh` keeps the observation store out of git the same way,
and ADR 0005 says why. A project that wants the entry tracked lands it in a PR of
its own.

An absolute path outside the repository needs neither the exclude nor the
worktree link. The glossary and the ADR directory are never excluded: they are
repository content.

## Never

- Build one of these paths from the git toplevel without reading the section.
- Move files already at an old location when the section changes. The project
  moves them, or leaves them.
- Resolve `CONTEXT-MAP.md` here. A multi-context layout is `kit:domain-modeling`'s
  own, and this section names only the single-context glossary.
