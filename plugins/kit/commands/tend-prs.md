---
model: sonnet
---

Sweep every open PR you own: triage the automated reviews that have landed, push
the fixes, enable auto-merge, and clean up the worktrees whose PRs have merged.

**Arguments:** none.

Each firing is one complete, self-contained pass. Run it from the main checkout.

**The intended way to run this is on a schedule, out of session** — install the
launchd agent with `plugins/kit/scripts/install-tending.sh` and it fires whether
or not anything is open. `/loop 20m /kit:tend-prs` does the same thing inside a
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

## Step 1 · `inventory` — Take the picture (run in parallel)

```
gh repo view --json nameWithOwner --jq .nameWithOwner
gh pr list --author @me --state open --json number,headRefName,url,title,isDraft,createdAt,labels
git worktree list --porcelain
git fetch origin main
```

Skip draft PRs in everything that follows — a draft is work you haven't finished
handing over.

`labels` is fetched here, in the one query the whole pass reads from, so the
hold check below cannot be reached with the label unread.

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
- **`triaged`** — the marker is present. Done here; merging is GitHub's job now.

### `kit-hold` — the human override

One label, applied from the GitHub UI, is how a person tells this command to
leave a PR alone. It works from a phone with no checkout, which is the point: the
motivating case is walking a change in the running app, where the PR must survive
a long verification session without being triaged, merged, or having its worktree
deleted underneath you. Re-requesting a review, hand-reviewing, and being
mid-rebase are the same shape.

Create it once per repo with `gh label create kit-hold`, or from the UI.

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
  --jq '[.[] | select(.body | startswith("<!-- kit-triaged -->"))] | length'
```

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
2. **Uncommitted work** — `git -C <worktree> status --porcelain`. Apply
   `/kit:cleanup-worktree` `Step 3`'s known-safe rule: untracked entries that are
   symlinks back into the main checkout are setup artifacts, not work. Anything
   else means you have work in progress there → skip and report.
3. **Someone is in it** — `lsof -d cwd 2>/dev/null | grep -F "<worktree>"`. A
   process whose working directory sits inside the worktree is a shell or an
   editor you left open → skip and report.

Step 3 replaces `/kit:cleanup-worktree` `Step 4`, which asks the user whether the
branch is checked out elsewhere. That question has a mechanical answer; this is
it. Do not ask it.

---

## Step 4 · `triage` — Address the review round

For each `untriaged` PR that passed `idle-check`, invoke `/kit:review-copilot <N>`
via the Skill tool, operating against that PR's worktree path.

It already does the whole job — fetches both reviewers, verifies every finding
against the code, applies or skips by its own policy, runs the project's gates,
commits with the per-item reasoning in the body, and pushes. Do not re-implement
or second-guess any of it. Tell it this is an unattended `/kit:tend-prs` run so
its `enable-auto-merge` step follows `merge-policy` below instead of prompting.

Then write the marker, whatever the outcome:

```
gh pr comment <N> --body "<!-- kit-triaged -->
<the Step 5 summary review-copilot produced>"
```

One comment serves as both the durable record on the PR and `classify`'s
idempotency signal. Post it even when nothing was fixed — *especially* then.

---

## Step 5 · `merge-policy` — Auto-merge by default, escalate by exception

On a clean triage, run `gh pr merge <N> --auto --squash`. With a single review
round there is nothing further to wait for, and leaving it off just means the PR
sits green until you notice it.

**Escalate instead — notify, leave auto-merge off — when any of these hold:**

- `/kit:review-copilot` skipped a **non-minor** item. That's a finding it judged
  real enough to record and too large to safely apply alone.
- The project's gates failed, or the push was rejected.
- `gh pr checks <N>` already shows a failing required check.

An escalated PR stays `triaged`, so later firings leave it alone and it waits for
you. Say which PR and which of the three reasons, so the notification is
actionable without opening anything.

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

Its `Step 4` is replaced by `idle-check`, per Step 3. Every other gate in it
stays: an unexpectedly dirty worktree still stops that one cleanup, and that is
the behavior you want from something deleting directories unattended.

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

Never notify on a quiet pass. A loop that pings every 20 minutes to say it did
nothing is a loop you will turn off.

---

## Stopping

`/loop stop`. Nothing here holds state between firings, so stopping and restarting
mid-flight is safe at any point.
