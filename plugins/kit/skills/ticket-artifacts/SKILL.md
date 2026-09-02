---
name: ticket-artifacts
description: Where a plan, a design brief, or a walkthrough is stored and how it is found again — one marked comment on the issue as the store, a gitignored local mirror as the cache. Use whenever a command writes or looks for one of those artifacts.
---

# Ticket Artifacts

Three artifacts in this suite outlive the session that produced them: the
**plan**, the **brief** it publishes, and the **walkthrough** that verifies the
result. They were stored three different ways — a comment, a gitignored file, a
file inside a worktree — with three different recovery paths and a hand-written
tiebreak for when two copies disagreed. The walkthrough had no recovery path at
all: reclaiming the worktree deleted it at exactly the moment someone might want
to re-run the walk.

This skill is the one rule. **An artifact about an issue is stored on the issue.**
The local file is a cache of that, not a second store.

## The store

One comment per kind, on the issue, opened by a marker on its own first line:

```
<!-- kit-artifact: plan -->
```

`plan`, `brief`, and `walkthrough` are the kinds. A fourth would need a reason —
the point of a fixed vocabulary is that a reader can enumerate what an issue
carries without knowing which command wrote it.

**Update the comment in place; never post a second one of the same kind.** Find
it with `gh issue view <n> --json comments`, match the marker, and edit by id:

```
gh api --method PATCH repos/{owner}/{repo}/issues/comments/<id> -f body=@<file>
```

An issue accumulating three superseded plans is worse than no plan, because the
reader has to date them before they can trust one. Rewriting is also what makes
the "which copy is newer" question disappear: there is one copy.

## The cache

Mirror the same body to `plans/<issue-number>-<kind>.md` at the repository root
of the **main checkout** — resolve it with `git rev-parse --show-toplevel`, never
a hardcoded path, and `mkdir -p` it. `/plans` belongs in `.gitignore`; add it if
it isn't there. `kit:start-ticket` symlinks the directory into every worktree,
so a worktree reads and writes the same cache as the checkout that owns it.

Write both in the same step, always. A command that writes only the comment
leaves the offline path broken; one that writes only the file has stored nothing
durable. The mirror costs a file write and buys the case that matters most in
practice — reading a plan with no network, in a worktree, mid-implementation.

**No issue number, no store.** A plan from a conversation that never became a
ticket goes to `plans/<short-slug>-plan.md` and stays local. There is nothing to
attach it to, and inventing an issue to hold it is worse than losing it.

## The read

1. **Local file first** — `<cwd>/plans/<n>-<kind>.md`. Free, and it's the copy a
   worktree already has.
2. **Then the marked comment.** If the file is absent, fetch the issue's comments
   and take the body under the marker. Write it back to the cache path as you go,
   so the second read in the same session is free.
3. **Then nothing.** Absence is a real answer — `plan-implementation` treats it
   as "no settled approach yet" and invokes `/kit:design`. Do not synthesize an
   artifact from the issue body to fill the gap.

Step 2 is what the whole scheme buys. A fresh clone, a removed worktree, a
scheduled run on a machine that has never seen this repo, a second developer —
each of those found nothing before, and each finds the artifact now. The symlink
is no longer the only path to a plan; it is a cache warmed by convenience.

**On divergence, the comment wins.** The two copies are written together, so they
diverge only when someone edited the local file by hand or a write half-failed —
and the comment is the copy another agent will read. Say which you took rather
than picking silently; a genuine contradiction usually means the issue was
re-scoped after the artifact was written, and that is worth a sentence.

## What the artifact contains

Owned by whoever writes it — `/kit:design` for the plan and brief,
`/kit:walkthrough` for the walkthrough. This skill owns only where it goes and
how it is found. One thing does cross: a stored artifact is read by an agent that
has none of the session it came from, so it must name interfaces and behavior
rather than file paths and line numbers. Concrete anchors rot, and the reader
pays for every one of them in verification.
