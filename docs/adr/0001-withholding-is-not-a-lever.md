# Triage labels a ticket it is not sure about, and lets the run park it

Triage used to withhold `ready-for-agent` from a ticket whose brief was not
settled, on the grounds that an agent would otherwise answer the open design
question inside a diff. Once the unattended path gained its own design pass, that
question became one the run could either settle or park on out loud — so
withholding bought nothing and cost visibility.

We decided triage always labels, and the run refuses. `ready-for-agent` was
narrowed to routing — who writes the code — and every other kind of "not quite
ready" is carried by a term that says which: `kit-blocked-by` for a dependency,
`kit-blocked` for the world, the kind for whether acceptance needs an eye.

## Considered Options

Withholding the label was the alternative, and it is the one that had been in
place. It fails on recoverability rather than on correctness: an unlabelled
ticket is invisible to the sweep no matter what has since landed, so it becomes
startable only through a re-triage nobody scheduled. A bulk mislabelling in
zcommerce left nineteen tickets unstartable for two days in silence, which is
the same failure through the other lever.

## Consequences

A ticket may now be selected, started, and parked — spending a worktree and a
model pass to arrive at a question triage could have seen. That is the price of
the refusal being legible, and it is paid per ticket rather than per queue.
