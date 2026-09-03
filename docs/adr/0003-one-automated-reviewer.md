# One automated reviewer, chosen for always being there

Partially superseded by [ADR 0004](0004-restore-the-pr-review-hook.md): the
hook this ADR removed was restored once its coverage argument stopped holding.
The rest of this decision — the scheduling loop it was bundled with staying
gone — is unchanged.

Two automated reviewers used to see every PR: GitHub Copilot, which fires
server-side, and a Claude headless review fired by a `PostToolUse` hook the
moment `gh pr create` returned. `/kit:review-copilot` merged their findings on
`(path, line)` and treated agreement across them as a stronger signal than either
alone.

The hook was the laptop half of a loop that now runs in GitHub Actions. Keeping
it would have meant keeping the machinery that made it reachable unattended — a
scheduled pass, its permission grant, its log file — which is a second
implementation of the loop CI already runs.

We decided that a reviewer which only fires when one particular machine is awake
is not a reviewer the workflow may depend on, and removed it. Copilot is the only
automated reviewer; the review prompt survives in
`plugins/kit/scripts/pr-review.sh` behind `/kit:start-review` and a direct run.

## Considered Options

**Keep the hook, drop the schedule.** The narrowest cut, and the one worth taking
seriously: the hook fires from an interactive session, so it needs none of the
scheduling machinery. Rejected because the coverage it buys is conditional on who
opened the PR and how — a PR opened from the web, from a runner, or from a
session without the hook registered gets one reviewer anyway, so the second
review is present exactly when it is least needed and absent whenever the work
was unattended. A reviewer you cannot predict cannot be reasoned about in the
merge decision.

**Move the Claude review into CI.** The version that keeps two reviewers
honestly. Not rejected on merit — it is a larger change, in the consuming
project's workflow rather than in this plugin, and it needs its own decision
about cost per PR. This ADR does not close that door.

**Say nothing and let the cross-reviewer logic go quiet.** Rejected because the
merge logic in `/kit:review-copilot` still reads as though two sources arrive,
and a reader hitting it would reasonably conclude the second one was broken
rather than removed.

## Consequences

Every PR gets one automated review. The agreement signal in
`/kit:review-copilot` never fires, so a finding is now acted on because it
verifies against the code, not because two reviewers agreed on it — the
verification step was always what made a finding actionable, and it is unchanged.

The CI gate keys on whether a review exists, and Copilot posts within about a
minute, so no trigger depends on the removed reviewer.

Restoring a second automated reviewer this way is [ADR 0004](0004-restore-the-pr-review-hook.md).
Moving the Claude review into CI instead — the second option above — is still
open if a reviewer independent of any hook registration is ever wanted.
