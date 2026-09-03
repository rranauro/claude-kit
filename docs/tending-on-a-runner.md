# Tending on a CI runner

A PR opens with auto-merge off. Copilot reviews it, CI goes green, and a
`workflow_run` job in the consuming project decides what happens next: a bash
gate answers the cheap questions, and where a judgement is genuinely needed it
calls `/kit:review-copilot <N> unattended`. Nothing runs on your laptop, and
there is nothing to start.

What follows is what that setup gets wrong when it is built the obvious way.

## Call `/kit:review-copilot <N> unattended`

A workflow already knows which PR woke it and has that branch checked out, so
there is no sweep to run and no worktree to survey. Point the runner at the one
command that does the judging, in unattended mode, where it writes the triage
marker and applies the merge decision itself.

What the runner gives up is the repair of a red check. That is deliberate:
repairing a check is not review triage, and a red PR is visible without anything
saying so.

## The gate must read `kit-hold` before it merges, not before it triages

A PR labelled `kit-hold` is one a person is in charge of, and the label is
usually on the PR before CI ever finishes — `/kit:new-pull-request` transcribes
it from the issue at creation time. It can also arrive later:
`/kit:review-copilot` writes it when someone declines auto-merge at its prompt,
which is the only record that the decline happened. Without the gate honouring
it, the next firing re-enables the thing they just declined. A gate that does not check it
merges the one PR a human deliberately asked to see first, and does so within
minutes.

The hold only ever withholds the merge. An unreviewed round on a held PR still
gets triaged — `/kit:review-copilot <N> unattended` runs the same as it would on
any other PR, verifies the findings, pushes what it fixes, and closes the round
at Step 7.5 — so a held PR does not sit unread until the person watching it
opens it themselves. What the hold changes is Step 8: finding `kit-hold` on the
PR, the pass reports the round as triaged and stops there, and never calls
`gh pr merge`. The gate has the same rule on its own later firings — a
`triaged` PR with auto-merge still off is the one place it would otherwise call
`gh pr merge` itself, and `kit-hold` is what tells it not to. Never remove the
label; clearing it is a human's to do.

## The round is closed by a marker, not by the run that closed it

`/kit:review-copilot` posts `<!-- kit-triaged -->` (or `<!-- kit-escalated -->`)
as a PR comment carrying its summary, and adds a `kit-triaged` label alongside it.
`workflow_run` fires again on every subsequent push, so a gate that does not look
for the record first re-triages a round already answered — paying for a model to
reach the same conclusion, and stacking a second summary comment on the PR saying
so.

**Read the label, not the comment.** The comment is authoritative and carries the
reasoning, but finding it costs a call per PR, and that cost is paid on every
firing whether or not there is work — which is the one cost that scales with the
polling interval rather than with the amount of work. The label is in the PR list
the gate already fetches. A PR with the comment and no label wakes a model that
finds the round closed and stops, which is the direction to fail in.

Skip an escalated PR on the same label. An escalation carries `kit-triaged` too,
because what it needs is a person rather than another model pass.

The round is closed by whoever closed it, not by the runner. A round handled in
someone's session writes the same record, so a gate that fires afterwards sees it
and stays quiet.

## Two automated reviewers, wherever the hook is registered

Copilot fires on every PR regardless. A project that has registered the
`pr-review-on-create` hook also gets a headless Claude review, posted as a
comment carrying the `<!-- claude-pr-review -->` marker, at `gh pr create` time
— `/kit:review-copilot` reads both and treats agreement on the same line as a
stronger signal. `/kit:start-review` still runs a review on demand regardless
of whether the hook is registered. Why the hook was removed, restored, and what
each trade cost, is [ADR 0003](adr/0003-one-automated-reviewer.md) and
[ADR 0004](adr/0004-restore-the-pr-review-hook.md).

## Every act GitHub attributes needs a user credential

`GITHUB_TOKEN` identifies the Actions bot, and a bot is not a person GitHub will
let drive a repository. Three separate acts each carry an identity, each takes
the credential from somewhere different, and each fails quietly on its own:

| Act | Where the identity comes from | What a bot identity costs |
|---|---|---|
| The commit | `bot_name` / `bot_id` on the action | A ruleset demanding attributed changes refuses it |
| The push | `token:` on `actions/checkout`, which persists it for git | CI returns `action_required` and waits for a click |
| The merge | Whoever enabled auto-merge | The PR's `Closes #N` never fires; the ticket stays open |

The third is the quietest. The link is registered, the keyword is in the body,
GitHub simply does not act on it for a merge performed as a bot — so the work
lands, the PR closes, and the ticket sits open with nothing reporting it.

Use a fine-grained personal access token for all three. Setting one and not the
others produces a pass that looks correct and is not.

## `check_suite` never arrives

GitHub refuses to trigger a workflow on a check suite that Actions created,
which is every check suite in a repository whose CI is Actions. A workflow
waiting on it never fires, and the failure is silent — there is no run to look
at, so the setup reads as working until someone notices every pass was started by
hand.

Use `workflow_run` on the CI workflow instead. It has one guard of its own: a run
whose push authenticated as `GITHUB_TOKEN` does not fire it. That guard is the
same rule as the table above, arriving a third way — a pass that pushes as the
bot never sees its own round return.

`workflow_run` only fires from the default branch's copy of the workflow file, so
a change to the trigger cannot test itself on its own PR.

## Let the gate do everything that is not a judgement

A model pass costs money and minutes; a bash job costs seconds. Only one thing on
a PR needs judgement — a review round nobody has closed, where each finding is
verified against the code. Enabling auto-merge on a PR already triaged and green
is not a judgement: the decision was made and recorded, and starting a model to
agree with it pays for a second copy of an answer already on the PR.

Answer the cheap questions in bash, and start a model for the one that is left.

## The pass runs under a grant that ships with the kit

Nothing on a runner is interactive, so a permission the pass does not hold is not
a prompt — it is a denial at the moment it acts. `/kit:review-copilot` spends its
model turns first and hits the wall last, which reads as a pass that ran, agreed
with itself, and changed nothing.

`scripts/tending-settings.json` is that grant, and a consuming project's workflow
merges its own gate commands over it. The split is what makes it reviewable: this
file says what a tending pass may do in any repo, the project's file adds the test
and lint commands it runs before pushing, and neither can quietly become the
other. Deny beats allow in the merged result, so a project can widen the grant and
cannot unlock what this one refuses.

The grant is easy to mistake for laptop leftovers, because it was written when a
runner script consumed it and no doc named it. It is not: the workflow reads it by
path out of the plugin checkout, from a repo that cannot be seen from here. Deleting
it fails the consuming project's workflow at `jq`, before the pass starts, and the
error names a file that exists in no repo you are looking at.

`gh pr edit` is allowed rather than denied, because the triage marker and the
`kit-hold` write above are both labels on the PR. That is the one act in the grant
that widens over time — every new label this kit writes needs it — so it is the
line to check when a pass reports a decision it could not record.

## A plugin is not installed by copying it

Copying a plugin's files into the workspace registers no commands. A pass whose
command does not resolve runs zero turns, exits in milliseconds, and reports
success — a false green is the failure this setup is least able to see. Assert on
the turn count.

Point `plugin_marketplaces` at the checkout already in the workspace, so the
plugin and the hooks that reference it are one commit.
