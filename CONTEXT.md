# Claude Kit

The commands that carry a ticket from triage to a merged PR without anyone
watching. The language below is what those commands read off an issue: the axes
that decide whether a ticket may start, who writes it, how its result is judged,
and what must happen before it merges.

## Language

### Ticket axes

**Kind**:
How a ticket's acceptance is asserted. Exactly one per ticket, applied at
triage. The switch the unattended design pass reads.
_Avoid_: type, category, class

**bug**:
A kind whose acceptance is a failing test that goes green.

**improve-codebase**:
A kind whose acceptance is the object-shape counts in
`kit:rails-codebase-design`. Applied only by the
`kit:improve-codebase-architecture` scan, which is where those counts come from.
_Avoid_: refactor, cleanup

**technical-debt**:
A kind whose acceptance is behavior preserved across the change. The same
subject as `improve-codebase`, surfaced by a human rather than the scan.
_Avoid_: refactor, chore

**user-experience**:
A kind whose acceptance is someone looking at the result. The only kind that
cannot be designed or judged unattended.

**ready-for-agent** / **ready-for-human**:
Who writes the code. A routing term and nothing else — neither says the brief is
settled, and neither is a comment on the ticket's quality.
_Avoid_: reading either as "ready", "vetted", or "approved"

**kit-blocked**:
The brief is finished and the world is not ready — a credential, a vendor
account, a decision outside the approach, a step no agent should take alone. Set
and cleared by a person; the commands read it and refuse to remove it.
_Avoid_: blocked, on hold

**kit-blocked-by**:
A parsed marker in the issue body naming the tickets that must close first. The
dependency edge; unlike `kit-blocked`, it clears itself when the blocker merges.

**kit-hold**:
The finished PR must be walked in the running app before it merges. Lives on the
issue and is transcribed onto the PR. Independent of kind.
_Avoid_: hold, do-not-merge

### Reclaiming a worktree

**Verdict**:
What a reclaim pass concluded about one worktree, combining three independent
answers into an action: `reclaim`, `reclaim-keep-branch`, or `hold`.
_Avoid_: status, eligible, stale

**Free**:
The worktree holds no work — nothing uncommitted, and no lock. Decides the
directory and nothing else, because a checkout is restorable and a branch is
not.
_Avoid_: idle, clean, abandoned, unused

**Accounted**:
The remote has received the branch's exact tip. The only question that decides
whether a branch may be deleted, and the only one a local test cannot answer.
_Avoid_: merged, safe to delete

### States a command produces

**Park**:
An unattended pass stopping at a question only a person can answer, saying which
question and on what. The sanctioned refusal — visible, reasoned, and resumable.
_Avoid_: block, fail, skip

**Withhold**:
Declining to label a ticket so the sweep cannot see it. An anti-pattern: it
refuses work silently and leaves nothing that clears itself. Park instead.
