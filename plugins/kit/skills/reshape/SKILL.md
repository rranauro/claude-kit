---
name: reshape
description: Reshape the namespaces a shape-held pull request touched, with the person at the hold choosing the move and the commits landing on that PR's branch — no ticket filed. Use when kit:ticket-loop hand-off holds a PR on shape findings and the person takes the reshape, or when a person runs /kit:reshape on a PR held by a shape review.
---

# Reshape

An **in-flight reshape**: a move across the namespaces one held PR touched,
chosen by the person at the hold and committed on that PR's branch. `CONTEXT.md`
defines the term; ADR 0007 says why it files no ticket.

**A person is the brief, so there is no unattended mode.** This pass shows,
ranks and asks; the person decides — which move, and whether any belongs inline
at all. A run with nobody present has nothing to offer and stops before step 1.

**Argument:** a pull request number.

## 1 — Confirm it is a shape hold

```bash
gh pr view <n> --json state,labels,headRefName,headRefOid,baseRefOid,comments
```

The PR must be open, carry `kit-hold`, and have a comment opening on
`<!-- kit-shape-review -->` with findings. Missing any, say which and stop —
the kind hold, a triage hold and a `kit:review-copilot` escalation are holds
about something other than shape, and this pass has nothing to say to them.

## 2 — Stand in the branch's worktree

Find it with `git worktree list --porcelain`, matching the PR's branch — a
`kit-hold` PR keeps reclaim off it, so it is usually there. Where it is not,
`git fetch origin <branch>` and create one on the existing branch through
`kit:worktree-conventions`; never a new branch.

Its head must be the PR's head. Behind → `git pull --ff-only`. Uncommitted
changes, or a local commit the PR lacks → say so and stop; that is someone's
work, and a reshape on top of it is not one they chose.

Take the lease as `kit:start-ticket` `create-worktree` writes it, and release it
however this pass ends — `git worktree unlock <worktree>`.

Every path below is that worktree's.

## 3 — Scope to the namespaces the PR touched

The scope is the outer constant — `kit:rails-codebase-design` §5 **Namespace**
— of every class the diff adds or changes:

```bash
git diff <base>...<head> --name-only
```

Nothing outside it is a candidate, even where a count fires. A finding beyond
the scope is a scan's, and naming it here turns a hold into a survey.

## 4 — Show the shape before proposing anything

One view per namespace, as its own message, ahead of any candidate:

```text
Ai::Prompts
├── Contract            initialize(site)          # added by this PR
│   ├── #rules -> Array<String>
│   └── #to_s -> String
│       consumers: ComponentGenerator (2), Ai::Request (1)
└── Assembler           initialize(site, contract)
    └── #prompt -> String
        consumers: Ai::Request (1)
```

Each class with its `initialize` and public members, the PR's additions marked,
and its consumers grouped by calling namespace with a count — one `git grep` for
references into the namespace, as `kit:rails-codebase-design` §2.5 **Separate
namespaces** finds them. That grouping is what a move will be judged against,
so the person reads it before reading a move.

If they want it drawn another way, name `/kit:show-me` — it is invoked by a
person only, so this pass cannot run it for them.

## 5 — Rank the candidates

Over the scoped classes only, apply `kit:rails-codebase-design` §2 counts, gate
on §3, and propose the §1.5 or §2.5 move each surviving count calls for. The
posted shape review's findings are the first leads, not the limit.

Per candidate:

- **The count**, by name, and its number.
- **The move**, and the After at the call site in §1.5's panels.
- **Outside the diff** — every call site the move would change that the PR did
  not add, as `file:line`. Find them in one `git grep` at the head, then drop
  the lines `git diff <base>...<head>` adds. None is an answer; say it. This is
  the line the person decides inline-versus-later on, so it is never left out
  and never summarised as a count.

Rank strongest first and recommend one, as §5 **Rank** defines it. Hold the
question to `kit:asking-a-human` — its register, and the reach on its own line.

Then ask which to take, or none. **Never say whether a candidate belongs inline
or in a ticket**; the call sites outside the diff are the evidence, and the
person weighs it.

**None** ends the pass. Nothing was written, and the hold is exactly as it was.

## 6 — Make the move

In the worktree, under the project's own test rules — named files and examples,
never a directory or the suite. Run the test files that cover each call site the
move reached, outside the diff included. Commit through `kit:commit`, then
`git push`. No force, no rebase, no merge of the base: the review round was
decided against this branch's history.

A move that will not go green after a real attempt: say so, discard the
uncommitted change, and stop. What was pushed before it stays.

Another candidate can follow. Return to step 5 against the new head; a moved
class changes what the remaining counts read.

## 7 — Report

Which moves landed and the head they left. The posted shape review is against
the old head — `/kit:shape-review <n>` judges the new one. `kit-hold` is still on
and is the person's to clear: `gh pr edit <n> --remove-label kit-hold`.

## Never

- File an issue, or offer to. A follow-up ticket is not this pass's exit.
- Remove `kit-hold`.
- Propose a move outside the scoped namespaces.
- Edit `kit:show-me` or `kit:improve-codebase-architecture`. Both are forks with
  an `UPSTREAM` sidecar.
