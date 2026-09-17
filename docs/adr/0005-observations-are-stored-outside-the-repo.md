# An observation is stored outside the repo, not on the issue

Every other artifact this suite produces is stored on the issue it is about, on
the argument that a local file is invisible to the next agent —
`kit:ticket-artifacts` states it, and a plan, a design brief and a walkthrough
all follow it.

An observation is the one exception. It is about the **process that was
running**, not about the ticket: a seam in a command, a rule that did not fire, a
premise that arrived unverified. There is no issue it belongs on. It goes to an
append-only store at the main checkout, `.claude/observations.jsonl`, excluded
per-clone through `.git/info/exclude` rather than `.gitignore` — many projects
commit `.claude/`, and an ignore rule there would be a tracked change in every PR
diff.

## Considered Options

**A standing collector issue, one comment per observation.** The alternative that
keeps the artifact rule intact, and the one that survives an ephemeral runner
where a file does not. Rejected on two counts: it puts a drawer of half-thoughts
in the backlog, where every listing and every sweep has to step over it, and it
makes every pass's close a network write.

**A new `kit:ticket-artifacts` kind.** Rejected by the reason above — the
artifact is not about the issue, so there is no issue to key it to.

**Leaving `/kit:pin-it` in place alongside it.** Rejected: two local drawers with
identical mechanics is the failure the store was built to prevent. `/kit:pin-it`
is retired and its dependents ported, which could not be split out — deleting it
first would leave `/kit:review-copilot` with no non-blocking destination at all.

## Consequences

A pass running where the checkout is discarded records nothing that survives.
`/kit:review-copilot unattended` on a `workflow_run` job is that case, and the
`kit-pinned` label carries the record there instead — which is why that step
applies the label before it attempts the append.

The store is unreachable by `scripts/lint.sh`, so a malformed line is both
unrecoverable and invisible. The record's shape is held by
`plugins/kit/scripts/observe.sh` and pinned by `tests/observe.sh`, and every
reader skips a line that will not parse rather than stranding the drawer.

Nothing counts the store on a schedule. Its size reaches a reader only because
the append prints it and the producing pass passes that line on.
