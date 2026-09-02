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

## One automated reviewer, not two

Copilot is the only reviewer that fires on its own. `/kit:review-copilot` still
merges overlapping findings across sources and calls agreement a stronger signal,
and with one source that half of it never fires — a real loss, taken knowingly.
The second reviewer it used to merge with ran headless from a hook on a
particular laptop, and a reviewer that only runs when one machine is awake is not
one anybody can rely on. `plugins/kit/scripts/pr-review.sh` still exists and
`/kit:start-review` still runs it on demand; nothing fires it automatically. The
decision and the alternative it beat are in
[ADR 0003](adr/0003-one-automated-reviewer.md).

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

## A plugin is not installed by copying it

Copying a plugin's files into the workspace registers no commands. A pass whose
command does not resolve runs zero turns, exits in milliseconds, and reports
success — a false green is the failure this setup is least able to see. Assert on
the turn count.

Point `plugin_marketplaces` at the checkout already in the workspace, so the
plugin and the hooks that reference it are one commit.
