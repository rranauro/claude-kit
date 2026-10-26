# The observation store is a queue: every record waits on a ticket or the owner

ADR 0005 framed an observation as being about the process that was running,
with a ticket-shaped finding going straight to the backlog instead. In practice
the store became where every finding outside a pass's scope landed, ticket-shaped
or not, under an action reading "this backlog" — and nothing said whether a
record was ready to file or waiting on a call only the owner could make. Records
that were tickets on the day they were written sat for weeks; records that were
an agent's call sat waiting on nobody.

So the store is the project's queue. Every record says what it waits on:
`ticket`, ready to file, carrying the decision the recording pass made; or
`owner`, a product call, one that contradicts an ADR, or one the code cannot
settle, carrying the question.
Any call an agent could make is made when the record is written. `observe.sh`
refuses a record that says neither, or whose action names only the backlog.

## Considered Options

**A pass files a ticket-shaped finding as an issue directly.** The shorter path
to the backlog, and the one ADR 0005's framing implied. Rejected for unattended
passes on ADR 0005's own grounds: a run of them floods the backlog with findings
nobody has looked at, and makes every pass's close a network write. Filing stays
a triage act, made by a person or a runner draining records marked `ticket`.

**Keep "a ticket" out of the store and leave the rest as it was.** Rejected: the
store already held them, and a rule the producers did not follow left the
records unlabelled rather than the store empty.

## Consequences

A review round on an unheld PR records each finding it could not decide as an
`owner` record, even though the PR body names it too: the PR can merge before
anyone reads its body. On a runner whose checkout is discarded that record is
lost, and the PR body and `kit-pinned` still carry the question.

Records written before `waiting` existed are untouched, and triage reads their
action to decide which they are. `observe.sh set-waiting` records that call in
place, so a record triage marks `ticket` keeps its place in the queue and is
drained by a runner rather than filed by hand.
