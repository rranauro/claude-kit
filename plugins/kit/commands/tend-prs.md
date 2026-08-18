---
model: sonnet
---

Sweep every open PR you own: triage the automated reviews that have landed, push
the fixes, enable auto-merge, and clean up the worktrees whose PRs have merged.

**Arguments:** none.

Each firing is one complete, self-contained pass. Run it from the main checkout.

**The intended way to run this is on a schedule, out of session** — install the
launchd agent with `plugins/kit/scripts/install-tending.sh` and it fires whether
or not anything is open. A firing with no judgment work to do costs no model at
all; see `## What the runner does before you`. `/loop 20m /kit:tend-prs` does the same thing inside a
session and is the way to watch a few passes before handing it over; it costs you
the session it runs in, and it only runs when you remember to start it.

This is the unattended half of the ticket workflow. `/kit:ship-ticket` carries a
ticket to an open PR while you're watching; this carries every open PR the rest
of the way while you're not.

**It never writes an implementation.** Every step here reacts to work a human
already approved — a review round, a merge. Starting a new ticket is a different
risk and lives in `/kit:start-next`, which you invoke deliberately.

---

## Mandatory constraints

- **Never ask a question.** Nobody is at the keyboard. Every delegated command
  below has interactive gates; the overrides are named explicitly per step. When
  a decision genuinely needs a human, notify and skip — do not guess, and do not
  wait.
- **Never touch a worktree that isn't provably idle.** `idle-check` is the
  precondition for every write. You may be working in one right now.
- **Derive all state from GitHub and git.** A firing knows nothing about the
  firings before it and must not need to.
- **Never merge locally.** `gh pr merge --auto` only.
- **Never write the `kit-hold` label, in either direction.** It is the one lever
  a human has over an unattended pass, and a lever this command can move is not
  one.
- **A permission denial is a finding, not an obstacle.** Running headless, the
  allowlist in `scripts/tending-settings.json` is the safety boundary, and a
  denied call means the boundary and this command disagree about what a pass
  needs. Record what was denied and what it was for, then carry on with the rest
  of the pass. Never route around one — a way around a boundary nobody widened
  on purpose is the thing the boundary exists to prevent.

---

## What the runner does before you

**This section is about unattended firings only.** Run by hand, you do every step
below yourself and nothing here applies.

The pass has two halves and only one of them needs a model. Verifying a review
finding against the code, and judging whether a skipped item is non-minor, is
judgment. The merge side is not: a merged PR is a fact GitHub reports, a worktree
either matches its branch or does not, `kit-hold` is a label read rather than
weighed, and fast-forwarding `main` is the same command every firing.

That mattered because the merge side is the *common* case. Firing every ten
minutes, roughly two thirds of passes had nothing to do but confirm it, and each
one spent a full context — re-reading this file and its delegates before printing
a line saying nothing happened.

So `tend-prs.sh` does the mechanical half in plain bash on every firing, before
it decides whether to start you at all:

| It has already done | Which is |
|---|---|
| Fetched and fast-forwarded `main` | `Step 6`'s sync, and the standing request that `main` carry what merged |
| Removed the worktrees and branches of merged PRs | `Step 6` entire |
| Surveyed every surviving worktree for idleness | `Step 3`, handed to you as verdicts |

Then it asks whether anything is left that needs judgment, and starts a model only
if so. Three things trip that gate, each mapping to a step below:

- reviews have landed and there is no triage marker → `Step 4` has a round to close
- a check is failing and the PR is not yet escalated → `Step 5` has one escalation to record
- the marker is present but auto-merge is off → `Step 5`'s stranding case

**The gate over-approximates on purpose, and it is not your classification.** It
answers the cheap question — "could there possibly be work here?" — and errs
toward yes, because a false yes costs one quiet pass while a false no strands a
PR forever. Every rule that decides what actually *happens* to a PR stays in this
file, in one place. So when the prompt names the PRs that tripped the gate, treat
that as the reason you were woken, not as an answer: derive each PR's state
yourself per `Step 2`, and be willing to conclude a listed PR needs nothing.

---

## Step 1 · `inventory` — Take the picture (run in parallel)

```
gh repo view --json nameWithOwner --jq .nameWithOwner
gh pr list --author @me --state open --json number,headRefName,url,title,isDraft,createdAt,labels,autoMergeRequest
git worktree list --porcelain
git fetch origin main
```

Skip draft PRs in everything that follows — a draft is work you haven't finished
handing over.

`labels` is fetched here, in the one query the whole pass reads from, so the
hold check below cannot be reached with the label unread. `autoMergeRequest` is
fetched for the same reason: `merge-policy` has to be able to tell a PR that was
left to merge from one that was left behind, and that answer is a field on the
PR rather than something a pass could remember.

---

## Step 2 · `classify` — What state is each open PR in?

**Copilot reviews on PR creation only, and the local Claude review fires from the
same create-time hook.** So a PR gets exactly one automated review round, and
this command's job is to catch that one round and close it out. There is no round
two to wait for. (Requesting a re-review is a deliberate human act — when you do
that, you disable auto-merge yourself, and `triaged` below keeps this command's
hands off.)

Each PR is in exactly one state:

- **`held`** — the PR carries the **`kit-hold`** label. Take no action of any
  kind: no triage, no auto-merge, no worktree removal. Report it as skipped and
  move on. Decide this **first**, before reading reviewer output or anything
  else — the point of a hold is that nothing further gets evaluated.
- **`awaiting-review`** — reviewer output incomplete. Do nothing; a later firing
  gets it.
- **`untriaged`** — both reviewers are in, no triage marker. This is the work.
- **`triaged`** — the marker is present. The review round is closed out, but this
  is **not** the end of the pass's interest in the PR: `merge-policy` still asks
  whether it is actually on its way to merging. See below.
- **`escalated`** — the marker is present *and* carries `<!-- kit-escalated -->`.
  A previous pass judged this one to need a human. Leave it entirely alone.

### `triaged` is not a terminal state

A PR reaches `triaged` the moment the marker is written, and the marker is written
whether or not auto-merge was then enabled. Those are two separate steps, and the
second one can fail to happen for reasons that have nothing to do with the PR: the
pass hit its timeout between them, `gh pr merge` errored transiently, the firing
was killed. Treating the marker alone as "done here, merging is GitHub's job now"
strands exactly those PRs — green, unheld, un-escalated, and passed over by every
subsequent firing forever, which reads to you as the command having quietly
stopped working.

So the marker closes out **triage**, not the PR. `merge-policy` runs against every
open PR the pass has not been told to leave alone, and the question it asks —
"does this PR have auto-merge on?" — is answered by `autoMergeRequest` from
`inventory`, freshly, on every firing. A PR that already has it is a no-op. A PR
that doesn't gets it, one firing later than intended rather than never.

Escalation is the one case that must survive, since a pass that re-enabled
auto-merge on a PR a previous pass deliberately held back would be worse than the
stranding. That is what `<!-- kit-escalated -->` is for: the reason a human is
wanted is recorded on the PR at the moment it is decided, so a cold restart
recomputes the same verdict from the same evidence.

### `kit-hold` — the human override

One label, applied from the GitHub UI, is how a person tells this command to
leave a PR alone. It works from a phone with no checkout, which is the point: the
motivating case is walking a change in the running app, where the PR must survive
a long verification session without being triaged, merged, or having its worktree
deleted underneath you. Re-requesting a review, hand-reviewing, and being
mid-rebase are the same shape.

Create it once per repo with `gh label create kit-hold`, or from the UI.

It can also arrive before you ever see the PR. `/kit:triage` and `/kit:design`
ask whether the downstream PR will need holding at the moment the ticket is
settled, record the answer on the issue, and `/kit:new-pull-request` transcribes
it onto the PR at creation — so a PR can be born held, which is the only way to
win the race against a pass that fires minutes later. That changes nothing here:
a human still made the decision, and this command still never writes the label.

**Never apply this label, and never remove it.** Not to record that a PR was
held, not to tidy up after a merge, not because the reason looks resolved. An
override the automation can clear is not an override — the whole guarantee is
that a human is the only writer, so a hold means what it meant when it was set,
however many passes ago. If a held PR looks like it should move, say so in the
report and leave the label alone.

Removing it is likewise a human act, and takes effect on the next pass with no
residue: `held` is read fresh from the label every firing and recorded nowhere,
so a PR that was held for a week classifies on its evidence the moment the label
comes off, exactly as if it had never been held.

This is the one piece of PR state that is genuinely **stored** rather than
derived, and that is correct — it encodes an intention that exists nowhere in the
repo or the PR's history. It is not a precedent for storing `untriaged` and
`triaged`. Those are sound *because* a cold restart recomputes them.

Detect reviewer output the way `/kit:review-copilot` `Step 2` does — Copilot's
inline comments and top-level review, plus the `<!-- claude-pr-review -->` marker
comment — and match logins case-insensitively for the reason that file gives.

**Wait for both, not either.** The two reviewers post independently: Copilot
lands 3–5 minutes after `gh pr create`, while the Claude review is a fresh
`claude -p` run whose finish time is its own. Treating "any reviewer output" as
the trigger means the common case — Copilot first — gets triaged against a Claude
review that hasn't arrived, and the marker then suppresses the pass that would
have caught it. Silent half-coverage, on most PRs.

So `untriaged` requires **both** sources present. The exception is a reviewer that
is never coming: if the PR was created more than **30 minutes** ago and only one
source has posted, proceed with what's there and name the missing reviewer in the
report. Take the PR's `createdAt` from `inventory` — the age is what distinguishes
"still coming" from "didn't run", and without the escape a hook that failed to
fire strands the PR forever.

Detect the triage marker:

```
gh api repos/{owner}/{repo}/issues/{N}/comments \
  --jq '[.[] | select(.body | startswith("<!-- kit-triaged -->")) | .body] | join("\n")'
```

Take the bodies rather than a count: the same read decides `triaged` versus
`escalated`, and a count cannot answer the second question.

**The marker is the only sound idempotency signal.** "Has the branch moved since
the review?" looks equivalent and isn't: `/kit:review-copilot` legitimately
produces no commit when every finding is a false positive or a non-minor
optional, and on those PRs a commit-based check re-triages the same findings on
every firing, forever. The marker is written whether or not anything was fixed,
which is exactly the case that distinguishes them.

---

## Step 3 · `idle-check` — Prove the worktree is free before writing to it

Run this for every PR before `triage` touches it, and for every worktree before
`cleanup` removes it. Skipping is always the safe outcome — the PR is still there
next firing.

`held` is checked before this, not by it. A hold is about intent and costs one
field you already fetched; `idle-check` shells out. Ordering them the other way
would mean proving a held worktree idle in order to then not touch it.

1. **Resolve the path** for the branch from the `git worktree list --porcelain`
   output. No worktree for the branch → notify and skip; the fixes have to be
   made somewhere, and this command does not create worktrees.
2. **Read the verdict.** Two questions decide it — whether the worktree holds
   uncommitted work (applying `/kit:cleanup-worktree` `Step 3`'s known-safe rule
   in full, both halves) and whether a process has its cwd inside it. Where the
   answers come from depends on who is running:
   - **Unattended**, `tend-prs.sh` surveys every linked worktree in plain bash
     after its own cleanup and immediately before invoking you — so the list
     describes the worktrees that survived this firing, not the ones it started
     with — and passes the verdicts in as
     `<path> <branch> <idle|busy> <reason>`. Use them as given. Do **not**
     re-derive them: you are not permitted to, and the attempt is what stalls the
     pass rather than something to work around.
   - **Attended**, derive them yourself — `git -C <worktree> status --porcelain`
     and `lsof -d cwd 2>/dev/null | grep -F "<worktree>"`.
3. `busy` → skip and report the reason verbatim. `idle` → proceed.

**A linter's cache daemon is not a holder.** The runner stops the ones it
recognizes before it answers, because they are not what this check is protecting.
An editor or a shell holds a cwd because a person is standing there; a `rubocop
--server` holds one because an autoformat hook started it behind you, and it is
reparented to init and idles on that cwd until the machine reboots. Reporting it
as busy defers the cleanup on *every* pass rather than a later one, which is the
opposite of what "deferred to a later pass" tells the reader. Attended, stop it
yourself when it is the only thing holding the worktree.

**Why the runner owns this unattended.** The check reaches a path that is not the
agent's cwd, and every form of that is either unmatched by the grant or unsafe to
grant: `git -C <path> status` fails the first-token rule, `cd <path> && git status`
fails it too (the first token is `cd`), and a `Bash(cd:*)` prefix would match a
compound command — putting every deny entry one `&&` away from being bypassed. So
the grant genuinely cannot express it, and the answer is the one
`docs/scheduled-tending.md` already reaches for with the escalation notification: the runner is plain bash,
outside the grant, and hands in what it found. A verdict computed seconds before
the pass starts is the same guarantee a check run inside it would give.

Step 3 replaces **both** of `/kit:cleanup-worktree`'s gates, and it is the same
verdict answering them:

- Its `Step 4` asks the user whether the branch is checked out elsewhere. That
  question has a mechanical answer; this is it. Do not ask it.
- Its `Step 3` checks the worktree for uncommitted work. That check *is* what
  produced the `idle`/`busy` verdict you were handed — the known-safe rule it
  describes was applied in full, both halves, to produce it. Unattended, do not
  run `git -C <worktree> status --porcelain` to re-derive it: the paragraph above
  is about that exact command, and the denial stalls the cleanup rather than
  deferring it. `busy` with an `uncommitted work:` reason **is** that step
  stopping the cleanup, reported the way it asks for.

Because the known-safe leftovers were already excluded to reach `idle`, an
`idle` worktree is one that step would have cleared with `--force` — which is
why the runner removes with `--force` and you do not need to flag it.

---

## Step 4 · `triage` — Address the review round

For each `untriaged` PR that passed `idle-check`, invoke `/kit:review-copilot <N>`
via the Skill tool, operating against that PR's worktree path.

It already does the whole job — fetches both reviewers, verifies every finding
against the code, applies or skips by its own policy, runs the project's gates,
commits with the per-item reasoning in the body, and pushes. Do not re-implement
or second-guess any of it. Tell it this is an unattended `/kit:tend-prs` run so
its `enable-auto-merge` step follows `merge-policy` below instead of prompting.

`/kit:review-copilot`'s own `Step 8` says to stop without enabling auto-merge when
this command invoked it. That is a handoff, not the end of the pass: it stops
*that* command precisely so `merge-policy` below can own the decision. Continue to
Step 5.

Then write the marker, whatever the outcome:

```
gh pr comment <N> --body "<!-- kit-triaged -->
<the Step 5 summary review-copilot produced>"
```

One comment serves as both the durable record on the PR and `classify`'s
idempotency signal. Post it even when nothing was fixed — *especially* then.

When `merge-policy` escalates, the marker carries a second line naming why:

```
gh pr comment <N> --body "<!-- kit-triaged -->
<!-- kit-escalated: gates could not be run (bundle exec rspec: command not found) -->
<the Step 5 summary review-copilot produced>"
```

Write the escalation reason into the marker in the same comment, not a later one.
A pass that posts the triage marker and then dies before recording *why* it was
escalating leaves a PR that looks merely triaged, which is the stranding this is
here to prevent — inverted.

---

## Step 5 · `merge-policy` — Auto-merge by default, escalate by exception

**This step runs against every open PR that is neither `held`, `escalated`, nor
`awaiting-review`** — the one triaged a minute ago in Step 4 and the one triaged
three firings back alike. Skip any whose `autoMergeRequest` from `inventory` is
already non-null; there is nothing to do and nothing to report.

On a clean triage, run `gh pr merge <N> --auto --squash`. With a single review
round there is nothing further to wait for, and leaving it off just means the PR
sits green until you notice it.

Re-running this on an already-triaged PR is safe by construction: enabling
auto-merge is idempotent, it is the only write this step makes, and the merge
itself stays GitHub's to perform once checks pass.

**Escalate instead — notify, leave auto-merge off — when any of these hold:**

- `/kit:review-copilot` skipped a **non-minor** item. That's a finding it judged
  real enough to record and too large to safely apply alone.
- The project's gates failed, **could not be run at all**, or the push was
  rejected. A gate that never ran is not a gate that passed, and unattended it is
  the likelier of the two — a scheduled job inherits no login shell, so a missing
  runtime looks like an environment note rather than a red build.
- `gh pr checks <N>` already shows a failing required check.

An escalated PR is recorded as such on the PR itself, via the `<!-- kit-escalated -->`
line in Step 4's marker, so later firings classify it `escalated`, leave it alone,
and it waits for you. Say which PR and which of the three reasons, so the
notification is actionable without opening anything — and put that same reason in
the marker, so the next pass has it too.

The first two reasons are things only the pass that ran the triage can observe. A
PR triaged by an earlier firing carries the answer in its marker or does not have
one, and "does not have one" means it was not escalated — do not re-derive it, and
do not treat the absence as a reason to withhold auto-merge. The third reason,
`gh pr checks <N>`, is live evidence and is checked on every firing regardless of
which pass did the triage.

If `gh pr merge` errors because auto-merge is disabled in repo settings, report it
once and move on — don't retry it every firing.

---

## Step 6 · `cleanup` — Remove the worktrees whose PRs have merged

```
gh pr list --author @me --state merged --limit 30 --json number,headRefName,mergedAt,labels
```

Intersect with the live worktrees from `inventory`. **A merged PR still carrying
`kit-hold` keeps its worktree** — drop it here and report it as held. Merging
does not retire the hold, and this is the case the override exists for: a
verification walk that outlives the merge still needs the worktree it is walking
in. `labels` is fetched on this query for that reason, not just the open one.

For each remaining match that passes `idle-check`, delegate to
`/kit:cleanup-worktree <branch>` — it verifies merge
state itself, stops per-directory daemons, removes the worktree, sweeps the husk,
syncs `main`, and deletes the branch.

Its `Steps 3 and 4` are replaced by `idle-check`, per Step 3 — that verdict
answers both, and re-deriving either is what stalls a pass. Every other gate in
it stays: a worktree the survey reports `busy` for uncommitted work still stops
that one cleanup, and that is the behavior you want from something deleting
directories unattended.

**Unattended, this entire step is the runner's and none of it is yours.** It has
already run by the time you start. Do not query merged PRs, do not nominate a
worktree for removal, and do not report cleanup — `tend-prs.sh` logs what it
removed itself, and a report claiming credit for it is just noise in the log.

That is not a permissions workaround; it is where the step belongs. Nothing here
needs judgment — a merged PR is a fact GitHub reports, a worktree either matches
its branch or does not, and `kit-hold` is a label read rather than weighed — so
the whole step reduces to `gh` output intersected with `git worktree list`. It
was worth moving because it was the *only* thing most firings had to do, and
starting a model to discover that cost a context per pass to accomplish nothing.
See `## What the runner does before you`.

Two parts of it genuinely could not stay here anyway, which is what made the
split obvious. `Step 5`'s husk sweep needs `rm`, and the grant denies `rm`
deliberately — a scheduled job composing a path to delete recursively, with
nobody watching, is the one thing worth keeping out of reach. And `Step 6`'s
branch delete has to happen *after* the worktree is gone, because git refuses to
delete a branch that is still checked out in one.

**Attended, do the whole step yourself** exactly as written above — you have the
permissions, and a person is there to answer the gates.

Do **not** delegate to `/kit:worktree-gc` here. It refuses to remove anything
without confirmation by design, and it sweeps orphan directories — neither
belongs in an unattended pass. It stays the human-run periodic catch for whatever
this command skipped.

---

## Step 7 · `report` — Say only what happened

Print one compact block: PRs triaged (with fixed/skipped counts), auto-merge
enabled, worktrees removed, and everything skipped **with its reason** —
naming `kit-hold` explicitly for anything held, since "held by kit-hold" and
"worktree dirty" are the difference between a deliberate act and a problem. The
skipped lines matter most — "worktree dirty, left alone" is how you find out this
command has been quietly declining to help for three days.

A firing where nothing was actionable prints a single line and nothing else.

**Print it even though nothing is watching.** On a scheduled run this block is
captured to `~/.claude/logs/tend-prs/<owner>-<repo>.log`, appended across every
pass, and it is the only record the firing leaves — there is no scrollback to go
back to. Write it for someone reading a week of passes at once, looking for the
skip that has been repeating.

**Printing it is the whole of writing it.** The runner redirects this pass's
output into that log itself; you have no file access outside the checkout and need
none. Do not try to append to the log — the denial you get is not a finding about
a boundary that is too narrow, it is the boundary correctly refusing a write that
was already done for you.

### Outstanding pins

Append one line when `<main-repo-root>/.claude/pins` holds anything — resolved
the way `/kit:pin-it` resolves it, from the common dir rather than the cwd:

```
3 pins outstanding, 1 stale (>30d): theme-preview-caching
```

Name only the stale ones; the rest are a count. A pin costs nothing to make and
nothing to keep, so the drawer fills quietly — this line is what makes an unread
pin visible without you having to remember the command exists.

It is a **report line, not an action**. Never read a pin's contents, never
triage one, never delete one: resurfacing is a conversation, and nobody is at
the keyboard. It also never fires a notification — pins are not urgent by
construction, and the quiet-pass rule below outranks them. A firing whose only
news is the pin count still prints its single line and stays silent.

**Fire a macOS notification only on escalation or a completed merge-enable:**

```
osascript -e 'display notification "<what happened>" with title "Claude Code" subtitle "<repo>" sound name "Glass"'
```

Keep the single quotes and the exact word order. The grant matches the command as
a literal string prefix, opening quote included, so `osascript -e "display ..."`
and any reordering are a different command as far as the boundary is concerned and
are denied. This is the one place in the pass where the phrasing of a command, not
just its effect, has to match.

Never notify on a quiet pass. A loop that pings every 20 minutes to say it did
nothing is a loop you will turn off.

---

## Stopping

`/loop stop`. Nothing here holds state between firings, so stopping and restarting
mid-flight is safe at any point.
