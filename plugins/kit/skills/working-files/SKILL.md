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
the toplevel one would, so a line copied between files cannot silently move.
**`plans` and `tickets` may also be absolute**, meaning outside the repository —
that belongs in `CLAUDE.local.md`, since no other developer has that directory.
`glossary` and `adr` may not: they are tracked content whose edits ship in the
caller's PR, and a file outside the checkout ships in none. Treat an absolute
one as absent and say so.

## What a caller gets back

**One absolute path per key**, so no caller picks its own base directory. A local
key (`plans`, `tickets`) is joined to the main checkout `kit:project-rules`
already resolved — never a worktree, where a cache dies with the ticket. A
tracked key (`glossary`, `adr`) is joined to the checkout the caller is writing
in, because its edits ship in that checkout's PR. An absolute local path is
returned as written. Say with each local one whether it is inside the repository.

**Resolve all four once per pass, from the single rules read, and reuse them.**
A caller that already holds `<plans>` from earlier in the pass uses it rather
than asking again.

**A local location is ready to write the moment it is resolved.** On its first
resolution in a pass, `mkdir -p` it and, if it is inside the repository, keep it
out of git:

```
git -C <main checkout> check-ignore -q <path relative to the root> \
  || echo "/<path relative to the root>" >> "$(git -C <main checkout> rev-parse --absolute-git-dir)/info/exclude"
```

`--absolute-git-dir`, because `--git-common-dir` answers relative to the
directory git was asked about, and appending from anywhere else misses the file.
Asked of the main checkout, its git directory is the common one every worktree
reads. `mkdir -p` the `info/` directory first if it is missing. So no writer creates,
excludes or defaults a location itself, and whichever writer touches it first, it
is handled the same way.

**Never edit a tracked `.gitignore` to do it.** These writes run from the main
checkout, usually on the default branch, so an added line is a tracked change no
ticket owns — it ships with whoever's PR picks it up next, or with nobody's.
`info/exclude` under the common directory is per-clone and covers every worktree
of it; `${CLAUDE_PLUGIN_ROOT}/scripts/observe.sh` keeps the observation store out
of git the same way, and ADR 0005 says why. A project that wants the entry tracked
lands it in a PR of its own.

The glossary and the ADR directory are never excluded: they are repository
content.

## Never

- Move files already at an old location when the section changes. The project
  moves them, or leaves them.
