---
name: project-rules
description: Find what a project says about how the kit runs there — which files hold its rules, which one wins when two speak, how a rule in the project's own words overrides a kit default, and where a setting may be recorded. Use whenever a command or skill reads a kit section such as `## Ship gate` or `## Worktrees`, before a GitHub write the kit has a default for, or when offering to record a setting.
license: MIT — Copyright (c) 2026 Ron Ranauro, https://github.com/rranauro/claude-kit
---

# Project Rules

The kit runs the way it does by default and takes direction wherever the project
states its own rules. Every reader of a kit section — `## Worktrees`,
`## Ship gate`, `## Review sources` and the rest — looks it up here, so that a
rule a developer wrote somewhere reasonable is never missed by one reader and
honoured by the next.

**This is shared mechanism, not an entry point.** The section's keys and what
they mean belong to the skill that reads it; this skill owns only where the
section is found.

## Where rules live

Up to four files, all optional:

| | Tracked | Per-developer |
|---|---|---|
| **Toplevel** | `CLAUDE.md` at the repository root | `CLAUDE.local.md` beside it |
| **Sub-project** | `CLAUDE.md` in the project the work is in | `CLAUDE.local.md` beside it |

**The sub-project** is the nearest directory below the root, holding the paths
being worked on, that carries its own `CLAUDE.md` — the app in a monorepo, such
as `rx/` holding the main app. The paths being worked on are the diff's, or,
before there is a diff, the ones the issue and its plan name. A repository with
one project has none, and so reads only the toplevel pair. **Paths spanning two
sub-projects, or naming none, read only the toplevel pair** — and say so where
the step reports, since a sub-project's rules were then not applied.

**Read `CLAUDE.local.md` from the main checkout, never a worktree.** It is
gitignored, so a fresh worktree does not have it, and its absence there says
nothing about the project. The main checkout is the first `worktree` line
of `git worktree list --porcelain`.

**Read them once per pass.** Resolve the sub-project and the main checkout, read
the files that exist, and take every section — and every sentence *Rules in the project's
own words* covers — from that read. Re-read a file only if the pass itself wrote
it.

## Which one wins

**Per section, and whole.** Find the section in each file that has it; the
winning file's section is the rule, with its lines as written. Never merge lines
from two files into one section — a merged section is a rule nobody wrote.

1. **Nearer wins.** The sub-project's files over the toplevel ones.
2. **At the same level, `CLAUDE.local.md` wins** over `CLAUDE.md`. It is where a
   developer puts what differs for them.

The same order settles *Rules in the project's own words* below: where two
files say different things about the same act, the winning file's sentence is
the rule.

**No file has the section → the kit's default.** A project that states no rules
sees exactly what it saw before any of them were read.

A section the reading skill says to take **from the base branch** is read from the base branch's
tracked files (`git show origin/<base>:<path>`), never the worktree's, and from
the main checkout's `CLAUDE.local.md`. The branch is the pass's own work; the
local file is the developer's.

## Rules in the project's own words

A project does not have to use a kit heading to be heard. **Anything these files
state about how the project uses GitHub — which labels it applies, how a PR
merges, what a PR body carries, which branch work starts from — governs the
matching act, under any heading or none, and beats the kit's default for it.**
"PRs merge with a merge commit" changes the merge the kit would arm;
"never apply `bug`; we use `Type: Bug`" changes the label it would write.

Apply it before each of those acts, from the sentences the first read noted. When a
rule and a kit default conflict and the rule is clear, follow the rule and say
so where the step reports. When it is genuinely unclear which act a sentence
governs, attended ask; unattended follow the kit's default and say which
sentence you could not apply.

## Labels

**A label a prompt file names is the canonical name of a role** — the spelling
`CONTEXT.md` defines, such as `bug`, `ready-for-agent` or `kit-hold`. Before
reading or writing one, take the project's spelling from what its rules say,
however they say it: "our bugs are `Type: Bug`", a table, a list under any
heading. That is the project's label mapping; there is no other.

- **The project names its own label for the role** → read and write that one,
  wherever the prompt file says the canonical name: a `--label` filter, an
  `--add-label`, a check of what a PR or issue carries.
- **The project says it has none** → skip the label. Do not write it, query on
  it, or wait for it. Where the label carries a decision, the step that makes
  the decision says what happens without it; the decision itself never loosens
  because its mark was skipped.
- **The project says nothing about it** → the canonical name, exactly as before
  any rules were read.

Say where the step reports which labels were translated or skipped. A reader
cites this section rather than restating it.

## Recording a setting

Some readers offer to record an answer so the next session need not ask again.
**The offer is a choice between `CLAUDE.local.md` and not recording it.** Write
the toplevel `CLAUDE.local.md` in the main checkout on the first answer, nothing
on the second. The kit never writes a tracked file to record a setting — a
project that wants a rule tracked lands it in a PR of its own.

**Unattended, offer nothing and record nothing.** A setting nobody chose is a
rule the pass granted itself.
