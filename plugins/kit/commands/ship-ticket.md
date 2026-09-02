---
model: opus
---

Carry a ticket to an open PR — worktree, plan, TDD, simplify, push. Takes the
tickets you name, or picks the next one whose blockers have all landed. Stops at
its gates so you can answer them, or runs the whole thing unattended.

**Arguments:** `$ARGUMENTS` — a selection, and optionally a mode.

The selection is one of three kinds:

- **Issue numbers** (`/kit:ship-ticket 612 613`) — the queue is what you typed,
  in the order given.
- **A label** (`/kit:ship-ticket bug`) — narrows the backlog sweep to the issues
  carrying it, without replacing its rules.
- **Nothing** — sweeps the whole backlog.

Every token that is digits means numbers; a single token that is neither digits
nor dash-prefixed is a label. **A mix of numbers and a label is a usage error** —
report it and stop rather than guessing which half was meant, since the two kinds
disagree about where the queue comes from.

Two flags modify it:

- **`--all`** makes a label the queue rather than a filter over one sweep. It
  needs a label — bare `--all` is a usage error, because an unbounded queue over
  the whole backlog is the one selection whose typo costs a worktree and a PR per
  open issue.
- **`--dry-run`** resolves the selection, reports it, and stops. Nothing is
  created, nothing is removed, and no ticket is started.

Flags are dash-prefixed and the mode is not. That is two grammars in one command,
and it is deliberate: a bare `all` would be indistinguishable from a label named
`all` under the rule above, while `--all` collides with nothing. `unattended`
stays bare because every invocation already written down spells it that way.

The mode is a trailing `unattended` token (`/kit:ship-ticket 612 unattended`, or
bare `/kit:ship-ticket unattended` to sweep). Without it this command is
attended: it stops at every gate and waits for you.

Run it from the main checkout.

**Selection and mode are independent.** The arguments decide *which* ticket; the
token decides *whether it asks*. Naming a ticket does not skip the gates, and
running unattended does not change what may be picked up.

**The loop itself is `kit:ticket-loop`.** This command owns only what happens once
per invocation, before any ticket exists: the reclaim sweep, then selection. That
skill owns the five phases and the one substitution that separates the modes — a
gate is a question attended, a rule-or-park unattended. Do not reproduce its
phases here.

What happens after the open PR happens on CI — `kit:ticket-loop` `hand-off` says
what, and Step 0 of the next invocation reclaims the worktree once the PR lands.
What is left for you is designing the tickets whose result someone has to look
at, answering the parks, and walking the PRs that carry `kit-hold`.

---

## Step 0 · `reclaim` — Clear the dead worktrees first

Before anything is selected or prepared, reclaim the worktrees this project has
accumulated. Invoke `kit:worktree-reclaim` through the **Agent tool**, unattended
and with no target, so it sweeps and asks nothing.

**Once per invocation, ahead of the whole queue** — not once per ticket. Naming
several tickets sweeps a single time before any of them is taken. It also runs
when selection goes on to take nothing: over an empty or fully blocked backlog
the sweep is the whole outcome rather than a preamble to one.

**Running here is what excludes the worktree this run will create.** Step 0
precedes selection, so that worktree does not exist yet and there is nothing to
exclude. Inside `kit:ticket-loop` or `kit:start-ticket` the exclusion would have
to be written down, and both are shared mechanism — a sweep added there lands on
every caller they have, at per-ticket cardinality.

**In a subagent, so the survey stays out of this session.** A verdict line per
worktree is exactly the inventory that crowds out the ticket the session is
actually for. What comes back is what was reclaimed and what was skipped with
reasons; nothing else.

**`--dry-run` skips this step.** Reclaiming removes worktrees and deletes
branches, so a dry run that reclaimed would not be dry. Step 1 says what that
costs the report.

**Best-effort.** A sweep that fails is one line in the report and selection
proceeds — nothing about reclaim may stop a ticket from starting. The accepted
cost, so nobody rediscovers it as a defect: a sweep that keeps failing degrades
to today's behaviour, where nothing is reclaimed at all.

Carry the agent's answer into Step 3 rather than acting on it here.

---

## Step 1 · `select` — Resolve the arguments to a queue

Selection has one job: turn the arguments into an ordered **queue** of issue
numbers and a list of **skips**, each carrying the reason it was skipped. Step 2
works the queue; Step 3 reports both. Three resolvers fill those two lists, one
per selection kind, and they differ only in where the candidates come from and
which checks apply.

### Named numbers — the queue is what you typed

`ready-for-agent` and the `kit-blocked-by` marker are query filters over work
nobody asked for, and you asked. Neither is required here.

Two checks still apply, because each is a claim about the world rather than about
labelling:

- **`kit-blocked`** — skip the ticket and report the reason from its "Blocked by"
  section. Naming a ticket is not clearing the flag.
- **An open blocker in its marker, if it has one** — skip and say which. The
  dependency has not landed, and that is true no matter who chose the ticket.

Work them in the order given, each one through Step 2 before the next starts. A
park on one ticket does not stop the queue.

### A label with `--all` — the queue is what the label names

```
gh issue list --state open --label <given> --json number,title,body,labels
```

Queue every one of them, lowest number first. This is the resolver above with the
typing removed, so it requires no label and no marker either — and it adds one
check the typed form does not:

- **Already started** — an open PR or a live worktree exists for the issue. Skip
  it and name the PR.

The asymmetry is about who chose the set. Typing nine numbers is knowing what you
typed; a label derives a set you never read, and a ticket stays open until its PR
merges. Without this check, running `bug --all` again while the first round is
still in review starts every one of them a second time.

### A bare label, or nothing — the sweep takes one

A sweep picks up work nobody named, so it reads the labels and the markers that
say a ticket was meant for an agent. A label narrows what it may choose from and
changes none of its rules:

```
gh issue list --state open --label ready-for-agent [--label <given>] --json number,title,body,labels
```

A ticket is **startable** when all of these hold:

1. Its body contains `<!-- kit-blocked-by: ... -->`. No marker means it was not
   filed as part of an epic — leave it alone. A sweep never picks up an arbitrary
   `ready-for-agent` ticket, only one whose author declared its edges.

   **The label requirement here is deliberate, and is not the one
   `kit:start-ticket` `plan-implementation` relaxed.** There a human has already
   named the issue, so the label merely corroborates a body you can read, and
   demanding it withholds work over a missing sticker. Here the label is the
   filter deciding what gets picked up at all, and dropping it would mean
   starting whatever happens to be open. Do not harmonize the two.
2. Every issue number in the marker is **closed**. `/kit:new-pull-request` writes
   `Closes #<issue>`, so a merged PR closes its ticket — a closed blocker means
   the work landed on `main`. An empty marker is trivially satisfied.
3. It does **not** carry the `kit-blocked` label — see below.
4. No open PR or live worktree already exists for it (it hasn't been started).

**Take the lowest startable issue number, and only that one.** Filing order is
dependency order, so the lowest is the earliest slice. One per sweep is what the
resolver is for: you asked for a ticket, and this is the one. `--all` is how you
ask for the set instead.

If nothing is startable, say which tickets are waiting and on what, in one line
each, then give Step 3's sweep line and stop — Step 0 already ran, and this exit
is the one place its report would otherwise be lost. Attended, that report is an
offer: name one and this command takes it, because naming is what clears rule 1.
Unattended it is the whole outcome, and a useful one — it tells you whether the
epic is blocked on a merge, on a person, or on nothing at all, and what the sweep
got back in the meantime.

### `--dry-run` — resolve it and stop

Report the queue in order and every skip with its reason, then stop. Do not
create a worktree, a branch, a PR, or an issue comment, and do not remove one.
A trailing `unattended` is moot: a dry run reaches no gate.

**Say that the queue was resolved against the worktrees standing now.** Step 0 is
skipped here — reclaiming removes worktrees and deletes branches, and a dry run
that does that is not dry — so a ticket reported as already started may be taken
by the real run once a stale worktree is reclaimed.

### `kit-blocked` — waiting on a person, not a merge

The marker in rule 2 carries one kind of edge: another ticket, cleared when a PR
merges and closes it. A machine clears it, which is why a sweep can read it and
act. Plenty of what actually holds a ticket back is not that shape — a credential
that has not been issued, a vendor account still in review, a change landing in
another repo, a decision you have not made, a migration whose production
reconcile is unwritten. None of those close an issue, so none of them can be
written as a number, and a ticket waiting on one is fully designed and correctly
labelled `ready-for-agent`.

`kit-blocked` on the **issue** is how that is said. It is the start-side twin of
`kit-hold`: same shape, other end of the pipeline. `kit-hold` stops a finished PR
from merging; `kit-blocked` stops a ready ticket from being started. Both are a
label read rather than weighed, and both are a human's to write.

Create it once per repo with `gh label create kit-blocked`, or from the UI.

**This command never applies or removes it.** Not to record that you skipped a
ticket, not because the reason reads as resolved, not because the blocking PR in
the other repo appears to have merged. Removing it is the human's statement that
the thing is actually cleared, and selection has no way to verify what it was
waiting on. The one place the label gets written is a park, and `kit:park` owns
that.

The reason lives in the issue body's `## Blocked by` section, alongside the
marker — the prose half of that section already exists for humans, and this is
what it is for. Read it and quote it when reporting:

```
2 tickets are ready but blocked on a person: #52 (Stripe account still in
review), #58 (needs the production reconcile decided). Clear with
`gh issue edit <n> --remove-label kit-blocked`.
```

If a `kit-blocked` ticket has no reason in its body, say so — a block nobody can
read is indistinguishable from one left on by accident.

**Name the labelled tickets you skipped for want of a marker, separately.** A
ticket carrying the AFK-ready label but no `kit-blocked-by` line is the one
failure a sweep cannot distinguish from a deliberate omission — rule 1 says leave
it alone, and that is right, but from the outside it is indistinguishable from
being ignored for no reason. Someone briefed and labelled that ticket expecting
it to be picked up:

```
3 labelled tickets have no kit-blocked-by marker, so they are not startable in a
sweep: #41, #43, #47. Add `<!-- kit-blocked-by: -->`, name one directly, or take
the whole label with `--all`.
```

Report it as information, not an error, and never add the marker yourself — the
edges are a human's call, and an empty marker written here would be this command
granting itself permission to start the ticket.

---

## Step 2 · `implement` — Run the loop

Invoke `kit:ticket-loop` via the Skill tool, once per selected ticket, passing
the issue number and the mode. It runs `prepare` → `tdd` → `simplify` →
`open-pr` → `hand-off`, halting at its gates when attended and applying the
matching rule when not.

Unattended, where no rule decides, it parks via `kit:park` — the decision goes on
the issue, `kit-blocked` goes on the label, the worktree and its commits stay put,
and the queue moves on. **A park inside the loop is already recorded**; carry its
reason into Step 3 rather than parking again.

---

## Step 3 · `report` — Say what happened

One paragraph. Which ticket was taken, what the PR number is, whether the plan
was stored or designed by this run, whether it carries `kit-hold` and so needs
your walkthrough, and — separately and by name — anything parked, with the
decision each one is waiting on.

**Split the parked list by what would clear it.** `kit:park` states the bins;
apply them rather than listing every park as one problem.

**Lead with the sweep**, in one line: what Step 0 reclaimed, and what it held or
skipped, with the reason. Say it when the sweep reclaimed nothing, and when it
failed. A sweep nobody is told about is worse than no sweep — running it where a
person is watching is the whole reason it sits in this command, and a report that
drops the line gives that up while still doing the work.

From here the CI gate takes over. Nothing runs on this machine until you invoke
this command again.

**A backlog sweep still takes one ticket per firing.** `/loop 20m
/kit:ship-ticket unattended` is how you work an epic that way, and one ticket per
firing is what keeps a park visible between firings rather than buried in a run
that kept going. A queue is the other shape — typed numbers, or a label with
`--all` — bounded by what you named rather than by the firing, and reporting its
parks together at the end.
