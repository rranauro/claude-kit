# An in-flight reshape files no ticket

A shape hold is the one point where an unattended run stops with a live branch
and a person in front of it, and moving code is cheapest before merge. So the
reshape `kit:reshape` offers there is chosen by that person and committed on the
held PR's branch, and nothing is filed. A ticket exists to brief an agent
working unwatched; at the hold the person steering is the brief, and writing
one down for them to hand back to themselves is a round trip with no reader.

## Considered Options

**File a ticket for every reshape the hold surfaces.** The path other
structural changes take. Rejected here: the move lands after merge, against code
the held PR has already spread to more call sites, and the ticket's agent redoes
the reading the person at the hold had just finished.

## Consequences

A reshape moves the head past the posted shape review, so that review describes
an older commit until it is rerun.
