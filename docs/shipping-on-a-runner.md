# Shipping on a local runner

`plugins/kit/scripts/ship-startable.sh <label>` takes every startable ticket
under a label to an open PR, one at a time, until the label runs dry — run
directly by the operator in a terminal, left running or backgrounded, with no
cron and no cloud scheduling. What follows is what that gets wrong when it's
built the obvious way.

## Every ticket gets its own `claude -p`, never a loop inside one session

`/kit:ship-ticket` takes exactly one ticket per invocation on purpose — a
second ticket in the same conversation carries the first one's context through
its worktree setup, TDD, and PR, and degrades quietly rather than failing
loudly. `/loop`'s dynamic self-pacing doesn't fix this: it fires the same
conversation repeatedly with a scheduled wakeup between turns, which is still
one process and one context growing across firings. The runner instead shells
out to a fresh `claude -p "/kit:ship-ticket <n> unattended"` per ticket and
blocks until it returns — that block *is* the pacing, and it's why nothing
here sleeps between one ticket finishing and the next one starting.

## The startable-ticket list has to be machine-readable, not ship-ticket's prose

`/kit:list <label>` exists so a script never has to parse `/kit:ship-ticket`'s
freeform Step 3 report to learn what's startable — it reads the same
`kit:startable-tickets` rule the sweep does and prints numbers a caller can
act on. The runner re-asks it every iteration rather than working from a list
taken once at the start: a ticket blocked on another one in the same epic
doesn't become startable until the blocker's PR merges and closes it, which
happens well after that ticket's own `claude -p` call has already returned.

The same "don't parse the prose" reasoning applies a second time, to a
question `/kit:list` doesn't answer: whether a PR this run already opened is
still open. The runner tracks that itself, by diffing `gh pr list` state
keyed on the `<issue>-` branch prefix `/kit:ship-ticket` created — never by
reading what the ship-ticket call printed.

## Nothing startable right now is not the same as nothing left to do

An epic where merges are automated has a ticket that's blocked when the list
is read become startable minutes later, once its blocker's PR closes its review
round, goes green, and merges. Exiting the first time nothing is startable stops
in the middle of a dependency chain the run was about to drain. The runner tells
the two cases apart by what it's still waiting on: if any PR it opened this
run is still open, it polls and tries again: if none are, the epic is
actually done.

## A silently-unresolved plugin command looks exactly like a clean run

`docs/tending-on-a-runner.md` names this failure for the CI gate — a pass
whose command doesn't resolve runs zero turns, exits fast, and reports
success. The same risk exists here: a `claude -p "/kit:list <label>"` or
`"/kit:ship-ticket <n> unattended"` call that returns in a few seconds with
nothing to show didn't find an empty backlog, it never ran. The runner floors
every call at a minimum duration and treats an under-floor return as a hard
stop, not a quiet "nothing startable" — the failure mode that's actually
dangerous to a run nobody is watching.

Unlike the CI gate, this runner doesn't need to construct a
`plugin_marketplaces` registration by hand: it relies on the target checkout's
own tracked `.claude/settings.json` (`extraKnownMarketplaces` +
`enabledPlugins`), the same project-level config that already makes `/kit:`
commands resolve for every interactive session against that repo. That's
`claude -p`'s *default* `--setting-sources`, not something the script adds —
which is also why `[[tend-prs-headless-constraints]]`'s finding that plugin
commands didn't resolve headlessly doesn't apply directly here: that probe
used `--setting-sources ''` to isolate a single passed-in grant, and excluding
project settings is exactly what makes the difference. Still worth a real
smoke test against one ticket before trusting the runner with a whole epic —
the floor-duration check above is the safety net if that assumption is wrong.

## The permission grant is broader than tending's, on the same split

`plugins/kit/scripts/ship-settings.json` is `tending-settings.json`'s
counterpart for shipping rather than reviewing — it grants `gh pr create`,
`gh issue edit` (for `kit-blocked` and `kit-hold`), and the git write commands
a full `kit:ticket-loop` pass needs, on top of everything tending already
grants. It still denies `gh pr merge`: shipping opens a PR and stops, the CI
gate decides whether it merges. A consuming project's own `--project-settings`
file merges its test and lint commands over this one before a run, the same
split `tending-settings.json` already uses — this file says what shipping a
ticket may do in any repo, the project's file adds how it verifies a change
before pushing.

## A crashed ticket needs no cleanup of its own

If a per-ticket call dies partway — the process is killed, the machine sleeps
— whatever worktree it left behind is exactly what a later
`/kit:ship-ticket` call's own Step 0 reclaim sweep picks up, because that
sweep runs unconditionally at the start of every invocation. The runner
doesn't track or clean up a dead worktree itself; a later ticket's own
startup does it for free.

*Later*, not next: the dead pass still holds the lease it took on that worktree
(`docs/worktrees.md`), and a sweep honours it until it expires. That is the price
of the lease being what stops a live pass losing its checkout — the two cases
look identical from outside, and the run that keeps working is the one worth
protecting. Nothing is lost meanwhile; the worktree is left exactly as it was.

## The safety valve is a hard cap, not a smarter startable check

If the startable rule is ever wrong in a way that makes the same ticket (or
an unbounded stream of tickets) look startable forever, nothing in the loop
detects that on its own — it isn't a judgment the runner is positioned to
make. The cap on tickets shipped per run is the answer instead: it stops the
run and says so, rather than trusting the check to catch its own failure.
