# A filed observation is shipped by number, not offered to the sweep

`ship-startable.sh --observations` drains the observation store one record at
a time: it files a record that waits on a ticket as an issue, ships it, and
drops the record once the issue has a pull request or a park. The issue it
files has to reach `/kit:ship-ticket` somehow, and the tracker must not become
the queue on the way.

The runner names the filed issue to `/kit:ship-ticket <n> unattended` itself.
The issue carries no `ready-for-agent` and no `kit-blocked-by` marker. A named
ticket is gated on neither, so nothing is lost by leaving them off.

## Considered Options

**File it startable under the run's label, and let the next `/kit:list` offer
it.** The issue would carry `ready-for-agent`, the run's label and an empty
marker, and the loop would need no path of its own. Rejected: every sweep on
that label could take it, so another runner or a `/loop` over
`/kit:ship-ticket` could start a ticket this run filed for itself. And a run
that died after filing would leave a ticket marked startable that nobody chose
to start, which is the backlog drawer ADR 0008 keeps out of the tracker.

## Consequences

A filed issue that never reaches a PR or a park is visible only as an
unlabelled issue, so the runner parks it itself when it cannot trace a result.
A person who wants such an issue swept rather than named adds the labels and
the marker by hand, as for any other ticket.
