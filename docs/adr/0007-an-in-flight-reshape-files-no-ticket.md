# An in-flight reshape files no ticket

A shape hold is the one point where an unattended run stops with a live branch
and a person in front of it, and moving code is cheapest before merge. So the
reshape `kit:reshape` offers there is chosen by that person and committed on the
held PR's branch, and nothing is filed. A ticket exists to brief an agent
working unwatched; at the hold the person steering is the brief, and writing
one down for them to hand back to themselves is a round trip with no reader.

## Considered Options

**File a ticket for every reshape the hold surfaces.** The path every other
structural change takes — `kit:improve-codebase-architecture` files its `Strong`
band, and a person who notices one files `technical-debt`. Rejected here: the move lands after
merge, against code the held PR has already spread to more call sites, and the
ticket's agent redoes the reading the person at the hold had just finished.
Filing remains a legitimate exit for a move the person judges too wide to take
inline; it is a separate path, not this one.

## Consequences

A reshape changes the head after the shape review was posted, so the review on
the PR describes an older commit. `kit:reshape` says so and names the rerun
rather than running it, and `kit-hold` stays until the person clears it.
