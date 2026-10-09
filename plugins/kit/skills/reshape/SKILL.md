---
name: reshape
description: Reshape the namespaces a shape-held pull request touched, with the person at the hold choosing each move — committed on that PR's branch with no ticket, or filed as a ticket blocked on the issues that PR closes. Use when kit:ticket-loop hand-off holds a PR on shape findings and the person takes the reshape, or when a person runs /kit:reshape on a PR held by a shape review.
---

# Reshape

An **in-flight reshape**, as `CONTEXT.md` defines it; ADR 0007 says why it files
no ticket. A candidate the person files as a ticket instead, step 6, has left
the reshape.

**There is no unattended mode.** This pass shows, ranks and asks, and the person
picks. A run with nobody present stops before step 1.

**Argument:** a pull request number.

## 1 — Confirm it is a shape hold

The PR must be open and carry `kit-hold`, and its latest `<!-- kit-shape-review
-->` comment must carry findings — found as `/kit:review-copilot` Step 2 finds
it, by marker and latest `updated_at`. Missing any, say which and stop: a hold
with no shape review is about something else, and this pass has nothing to say
to it.

**Compare the review's heading SHA with `headRefOid`.** Where they differ, say
so: the posted findings describe a head the branch has moved past — a review
round's fixes, or an earlier reshape — and may already be fixed. Step 3 then
counts everything afresh rather than starting from them.

Read the PR's `closingIssuesReferences` in the same lookup — the field
`kit:startable-tickets` `already-carried` reads, from this one PR. Step 4 needs
it to decide whether step 6 is on offer, and step 6 writes it into the ticket.

## 2 — Stand in the branch's worktree

**`kit:ticket-loop` as the caller** is already in it, at the PR head, holding
the lease. Skip to step 3, and leave the lease alone — it is the loop's, and
step 4 of its `hand-off` still needs it.

**Run by a person**, find it in `git worktree list --porcelain` by the PR's
exact `headRefName` — not by an issue prefix, since a PR shape-reviewed by hand
may close no issue, or several. A `kit-hold` PR keeps reclaim off its worktree,
so it is usually there. Where it is not, create one on the PR's existing branch through
`kit:worktree-conventions` — never a new branch — and wire it as
`kit:start-ticket` `wire-worktree` does. Take the lease as `create-worktree`
writes it, and release it however this pass ends.

Either way, the worktree's head must be the PR's. Behind →
`git pull --ff-only`. Uncommitted changes, or a local commit the PR lacks → say
so and stop; that is someone's work, and a reshape on top of it is not one they
chose.

## 3 — Gather the evidence in a subagent

Through the **Agent tool**, so the inventory stays out of this session — wait
for it to return. It works at the PR head, and reads the diff and the references
once each, then answers from them:

```bash
git diff -U0 <base>...<head>                  # touched files, and the added lines
git grep -n -E '\b(<Namespace>|<Class>|<member>|…)\b' <head>   # every reference into the scope
```

The pattern carries the scoped classes' bare names and their public members as
well as the namespace: code inside a namespace reaches its siblings unqualified
(`Contract.new` within `module Ai::Prompts`), and a namespace-only search drops
exactly those call sites from the list the person decides on.

- **The scope** is the outer constant — `kit:rails-codebase-design` §5
  **Namespace** — of every class the diff adds or changes. Nothing outside it is
  a candidate, even where a count fires: that is a scan's finding, and taking it
  here turns a hold into a survey.
- **The shape** — per namespace, each class with its `initialize` and public
  members, the PR's additions marked, and its consumers grouped by calling
  namespace with a count. The grouping is what a move is judged against.
- **The candidates** — the scoped classes judged as `kit:shape-review` §2–3
  judges a diff's, placement included, over the scope rather than the diff. The
  posted review's findings stand as counted only where step 1 found its SHA is the head.
  Each candidate carries its count and number, its move (§1.5 or §2.5) and the
  After in §1.5's panels, and **outside the diff**: every reference row above
  the move would change that the diff did not add, as `file:line`. None is an
  answer. Ranked strongest first, one recommended, as §5 **Rank** defines it.

## 4 — Show the shape, then the candidates

The shape first, as its own message, before any candidate — the person reads
what the namespace is before reading what it could become:

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

If they want it drawn another way, name `/kit:show-me` — it is invoked by a
person only, so this pass cannot run it for them.

Then the ranked candidates, held to `kit:asking-a-human`, with each one's call
sites outside the diff listed in full — never summarised as a count. Ask which
to take, and for each, whether **inline** — step 5, on the held branch — or **as
a ticket** — step 6, blocked on the issues the held PR closes. Or none. **Offer
the ticket only where the PR closes at least one issue**; where it closes none,
say so and offer inline or none.

**Never say whether a candidate belongs inline or in a ticket.** The call sites
outside the diff are the evidence; the person weighs it.

**None** ends the pass. Nothing was written, and the hold is exactly as it was.

## 5 — Make the move

In the worktree. Commit through `kit:commit`, which runs the tests over every
file the move changed — the call sites outside the diff included — then
`git push`. No force; and never integrate the base, `kit:ticket-loop`'s rule.

A move that will not go green after a real attempt: say so, discard the
uncommitted change, and stop. What was pushed before it stays.

Another candidate can follow. Recount only the classes the move touched and
their consumers, and re-show what changed in the ranking before asking again.

## 6 — File it as a ticket

The edge is every issue in `closingIssuesReferences`. That is the point of
filing here: a ticket filed by hand later carries no edge, and
`kit:startable-tickets` conditions 1–2 say what an absent or empty marker does
to it — never start it, or start it before the held PR merges.

Draft it through `kit:writing-tickets` — the candidate's move as the problem,
its call sites outside the diff as the evidence, the held PR linked — with the
marker naming those issues in `kit:to-tickets` 5a's form. The issues already
exist, so it is one create; 5a's second pass does not apply. Show the draft and
create it only on approval; a no files nothing.

No `ready-for-agent` and no design: routing is `/kit:triage`'s, the approach
`/kit:design`'s. Until triage labels it, no sweep sees the ticket, however its
blockers stand — the marker holds it back once routed, and does not route it.
Nothing is committed or pushed, so the next ask needs no recount.

## 7 — Report

Which moves landed and the head they left, and which tickets were filed,
with their numbers and `/kit:triage <n>` beside each — unrouted, a sweep never
starts one. Where a move landed, the posted shape review is against the
old head — `/kit:shape-review <n>` judges the new one. `kit-hold` is still on
and is the person's to clear: `gh pr edit <n> --remove-label kit-hold`.

## Never

- File an issue the person has not approved.
- Remove `kit-hold`.
- Propose a move outside the scoped namespaces.
- Edit `kit:show-me` or `kit:improve-codebase-architecture`. Both are forks with
  an `UPSTREAM` sidecar.
