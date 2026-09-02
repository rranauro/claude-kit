# CLAUDE.md project standards

## Project Context

This repository *is* a Claude Code plugin. Its payload is prompt files —
commands, skills, hooks and the shell scripts they call. `CONTEXT.md` holds the
vocabulary those files read off an issue; `docs/commands.md` lists the surface;
`docs/why.md` carries the reasoning. Read those rather than restating them here.

## Non-negotiable project rules

- **The deliverable is prose an agent reads, not code a machine runs.** There is
  no test suite and nothing to unit-test. Do not offer to add specs, and do not
  treat their absence as a gap.
- **`scripts/lint.sh` is the whole automated check** — shell parses, JSON
  manifests are JSON, skill frontmatter matches its directory. All three fail at
  harness load time rather than at review. Run it before opening a PR;
  `.github/workflows/lint.yml` runs it again on the PR.
- **The design skills this plugin ships do not govern this plugin.**
  `kit:rails-codebase-design` and `kit:behavior-placement` are the axis for the
  Rails projects that consume the kit. Nothing here is a Rails class, so there is
  no behavior to place and nothing to score. Scoring markdown on object-shape
  counts is the failure this rule exists to prevent.
- **Worktrees live inside the checkout**, under `.claude/worktrees/`. Every
  recursive search reaches a full copy of the repo per open ticket, so prune it:
  `find . -path ./.claude/worktrees -prune -o …`, and `grep -r --exclude-dir` or
  `rg`, which honours `.gitignore`. A result set with the same file five times is
  this rule going unread.
- **`plans/`, `tickets/`, `reviews/` and `.claude/worktrees/` are gitignored
  local state**, not part of the plugin payload. Nothing in them ships, and
  nothing in them survives a fresh clone — so never make a prompt file depend on
  one being present.
- **An adopted skill is a fork.** A skill carrying an `UPSTREAM` sidecar was
  vendored by `scripts/adopt-skill.sh` from an upstream repo, and
  `scripts/check-upstream.sh` reports what has changed there since. Editing one
  by hand diverges the fork silently. A skill with no sidecar is ours outright.
- **Never commit to `main`.** Feature branch off `origin/main` — `git fetch
  origin main` first so the local ref is not stale — then a PR. PRs are merged on
  GitHub, never locally.
- **Every PR opens with auto-merge on.** `gh pr merge <N> --auto --squash`
  immediately after `gh pr create`. `lint` is a required check, so CI is the
  gate; nothing merges red. Withhold `--auto` only when you want a human to look
  before it lands, and say in the handoff that you did. The kit's own rule of
  holding auto-merge off until a review round is triaged is written for repos
  with a bot reviewer — this one has none, so there is no round to wait for.
- **Work this repo through its own commands.** `/kit:architect` and
  `/kit:triage` for what to build, `/kit:design` for how, `/kit:ship-ticket` to
  carry it. A change to the workflow that was not made through the workflow has
  not been tried.

## Where a fact goes

Four layers describe this system, and a fact written into the wrong one becomes a
second source of truth that drifts. Find the layer that already owns it before
writing anything down.

| Layer | Owns | Test before writing |
|---|---|---|
| The prompt file | Its own mechanism — what the command does, in the order it does it | Would an agent following this file get it without being told twice? Then it is already written. |
| `CONTEXT.md` | Vocabulary — what a term means, and the synonyms to avoid | Would this still be true if the mechanism changed? If not, it belongs in the file that implements it. |
| `docs/*.md` | Invariants spanning several files, cross-cutting workflows, gotchas, and why a thing is the way it is | Does it say what breaks, or why, rather than what exists? |
| `docs/adr/` | A decision with a rejected alternative | Would someone credibly propose the alternative again next quarter? |

## Writing

- These files are read by a model under load. Invoke the `writing-for-agents`
  skill before creating or substantially editing a command, skill, or hook.
- Comment the *why*, never the *what*. The scripts in `plugins/kit/scripts/` and
  `scripts/` are the pattern: a header saying what the file is for and which trap
  it exists to avoid, never a narration of the lines below.
- No ticket-number banners and no file-level prose headers on new code. The PR
  and git history carry that.
- Docs state the invariant that holds now, never how it came to hold. Cite an
  issue number only where it names something still live — deferred work, an open
  decision — never to attribute a change.

## Never

- Add a changelog, a roadmap, or a design/exploration doc.
- Restate `CONTEXT.md`, `docs/commands.md`, or `docs/why.md` in another file.
- Write a memory file. Workflow knowledge belongs in `docs/`, where it is
  reviewable in a PR and versioned with the code.
