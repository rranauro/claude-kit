---
model: opus
---

Carry one ticket to an open PR — worktree, plan, TDD, simplify, push. Takes the
ticket you name, or picks the next one whose blockers have all landed. Stops at
its gates so you can answer them, or runs the whole thing unattended.

**Arguments:** `$ARGUMENTS` — a selection, and optionally a mode.

**The selection names at most one ticket**, in one of three kinds:

- **An issue number** (`/kit:ship-ticket 612`) — that ticket.
- **A label** (`/kit:ship-ticket bug`) — narrows the backlog sweep to the issues
  carrying it, without replacing its rules. The sweep still takes one.
- **Nothing** — sweeps the whole backlog, and takes one.

A token that is digits is a number; a single token that is neither digits nor
dash-prefixed is a label.

**More than one number is a usage error, and so is a number alongside a label.**
Report which it was and start nothing — not the first number, not any of them.
Shipping a fifth of what was typed is the outcome an operator then has to
reconcile by hand, and *One ticket, one invocation* below says where a run of
several belongs.

One flag modifies it:

- **`--dry-run`** resolves the selection, reports it, and stops. Nothing is
  created, nothing is removed, and no ticket is started.

Any other flag is a usage error. **`--all` especially** — point at *One ticket,
one invocation* below, which says where choosing a set and running a set live
instead.

Flags are dash-prefixed and the mode is not. That is two grammars in one command,
and it is deliberate: a bare `dry-run` would be indistinguishable from a label of
that name under the rule above, while `--dry-run` collides with nothing.
`unattended` stays bare because every invocation already written down spells it
that way.

The mode is a trailing `unattended` token (`/kit:ship-ticket 612 unattended`, or
bare `/kit:ship-ticket unattended` to sweep). Without it this command is
attended: it stops at every gate and waits for you.

Run it from the main checkout.

**Selection and mode are independent.** The arguments decide *which* ticket; the
token decides *whether it asks*. Naming a ticket does not skip the gates, and
running unattended does not change what may be picked up.

## One ticket, one invocation

A second ticket in the same invocation runs in a context that has already carried
the first through worktree setup, plan verification, TDD, simplify and a PR, and
nothing downstream degrades gracefully as that fills. Work gets quietly worse,
then a run ends mid-ticket and leaves a half-built worktree with no park comment
to explain it. Size is not the variable — one extra ticket is the same defect in
a smaller dose — so this command has no way to name a set, and both of the things
naming one would do belong elsewhere:

- **Choosing what to work on is a listing question.** `/kit:list <label>` reports
  the open tickets a sweep would actually start — same rule, same skill — and its
  output is numbers you hand back here one at a time.
- **Running several in succession is the caller's job.** Each ticket needs a
  context that carried no previous ticket, so each ticket needs its own process,
  and nothing inside one invocation can give it that. #101 is the kit's runner
  for it.

A flag that takes a set is this section going unread.

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

**Wait for the agent to return before Step 1 begins.** The Agent tool returns
when the sweep is *launched*, not when it is finished, so the sequencing above
does not hold anything back on its own. Selection reads worktree state too —
`kit:startable-tickets` consults `git worktree list` on the sweep path — and so
does `kit:start-ticket` `safety-check`, which decides resume-or-replace from it.
A sweep still in flight can reclaim a worktree between the moment one of those
reads it and the moment it is used.

**Ahead of selection, and it runs even when selection goes on to take nothing.**
Over an empty or fully blocked backlog the sweep is the whole outcome rather than
a preamble to one.

**Running here is what excludes the worktree this run will create.** Step 0
precedes selection, so that worktree does not exist yet and there is nothing to
exclude. Inside `kit:ticket-loop` or `kit:start-ticket` the exclusion would have
to be written down, and both are shared mechanism — a sweep added there lands on
every caller they have.

**In a subagent, so the survey stays out of this session.** A verdict line per
worktree is exactly the inventory that crowds out the ticket the session is
actually for. What comes back is what was reclaimed and what was skipped with
reasons; nothing else.

**`--dry-run` skips this step.** Reclaiming removes worktrees and deletes
branches, so a dry run that reclaimed would not be dry. Step 1 says what that
costs the report.

**Best-effort.** A sweep that fails, or that does not return, is one line in the
report and selection proceeds — nothing about reclaim may stop a ticket from
starting, and waiting for it may not turn a stuck sweep into a stuck command.
The accepted cost, so nobody rediscovers it as a defect: a sweep that keeps
failing degrades to today's behaviour, where nothing is reclaimed at all.

Hold the agent's answer from here and use it at Step 3. Nothing between the two
acts on it.

---

## Step 1 · `select` — Resolve the arguments to a ticket

Selection has one job: turn the arguments into **one issue number, or none and
the reason why**. Step 2 works it; Step 3 reports it. Two resolvers do that — a
number you typed, and a sweep the other two kinds share — and they differ in
where the candidate comes from and which checks apply.

### A named number — the ticket is the one you typed

`ready-for-agent` and the `kit-blocked-by` marker are query filters over work
nobody asked for, and you asked. Neither is required here.

Three checks still apply, because each is a claim about the ticket or the world
rather than a routing sticker:

- **`epic`** — refuse it and say so. There is nothing in a container to
  implement, so naming one is a mistake rather than permission.
- **`kit-blocked`** — refuse it and report the reason from its "Blocked by"
  section. Naming a ticket is not clearing the flag.
- **An open blocker in its marker, if it has one** — refuse and say which. The
  dependency has not landed, and that is true no matter who chose the ticket.

### A bare label, or nothing — the sweep takes one

A sweep picks up work nobody named, so it reads the labels and the markers that
say a ticket was meant for an agent. Invoke `kit:startable-tickets` via the Skill
tool, passing the given label if there is one — it owns the candidate query and
the five conditions, and it hands back the startable tickets plus every excluded
one with its reason. A label narrows what it may choose from and changes none of
its rules.

**Take the lowest startable issue number, and only that one.** Filing order is
dependency order, so the lowest is the earliest slice: you asked for a ticket,
and this is the one.

Everything else that skill returns is what the sweep excluded, which Step 3
reports.

If nothing is startable, say which tickets are waiting and on what, in one line
each, then give Step 3's sweep line and stop — Step 0 already ran, and this exit
is the one place its report would otherwise be lost. Attended, that report is an
offer: name one and this command takes it, because naming is what clears the
marker condition. Unattended it is the whole outcome, and a useful one — it tells
you whether the epic is blocked on a merge, on a person, or on nothing at all,
and what the sweep got back in the meantime.

**`/kit:list <label>` answers this without starting anything.** Same rule, same
skill, so a ticket it names is one this command will take.

### `--dry-run` — resolve it and stop

Report the ticket it resolved to — or that there is none, and why — along with
everything a sweep excluded and its reason, then stop. Do not create a worktree,
a branch, a PR, or an issue comment, and do not remove one. A trailing
`unattended` is moot: a dry run reaches no gate.

**Say that it was resolved against the worktrees standing now.** Step 0 is
skipped here — reclaiming removes worktrees and deletes branches, and a dry run
that does that is not dry — so a ticket reported as already started may be taken
by the real run once a stale worktree is reclaimed.

## Step 2 · `implement` — Run the loop

Invoke `kit:ticket-loop` via the Skill tool with the selected issue number and
the mode. It runs `prepare` → `tdd` → `simplify` → `open-pr` → `hand-off`,
halting at its gates when attended and applying the matching rule when not.

Unattended, where no rule decides, it parks via `kit:park` — the decision goes on
the issue, `kit-blocked` goes on the label, and the worktree and its commits stay
put. **A park inside the loop is already recorded**; carry its reason into Step 3
rather than parking again.

---

## Step 3 · `report` — Say what happened

One paragraph. Which ticket was taken, what the PR number is, whether the plan
was stored or designed by this run, whether it carries `kit-hold` and so needs
your walkthrough, and — if it parked — the decision it is waiting on.

**Name the bin a park is in.** `kit:park` states them; the bin is what tells you
whether the answer is yours to give or the world's to deliver.

**An epic is refused, not parked.** Nothing clears it and nothing is waiting on a
decision, so it is reported with its reason alongside what a sweep excluded:

```
#12 is an epic, so it is a container rather than a ticket and was not started.
Its slices are what a sweep picks up.
```

**Quote a `kit-blocked` reason** from the issue body's `## Blocked by` section,
and say how it is cleared — the label is a human's to remove, never this
command's:

```
2 tickets are ready but blocked on a person: #52 (Stripe account still in
review), #58 (needs the production reconcile decided). Clear with
`gh issue edit <n> --remove-label kit-blocked`.
```

**Name the tickets skipped for want of a marker separately**, as information
rather than an error, and never add the marker yourself — the edges are a human's
call, and an empty marker written here would be this command granting itself
permission to start the ticket:

```
3 labelled tickets have no kit-blocked-by marker, so they are not startable in a
sweep: #41, #43, #47. Add `<!-- kit-blocked-by: -->`, or name one directly.
```

**Lead with the sweep**, in one line: what Step 0 reclaimed, and what it held or
skipped, with the reason. Say it when the sweep reclaimed nothing, and when it
failed. A sweep nobody is told about is worse than no sweep — running it where a
person is watching is the whole reason it sits in this command, and a report that
drops the line gives that up while still doing the work.

From here the CI gate takes over. Nothing runs on this machine until you invoke
this command again.

**Every selection takes one ticket, so a backlog is worked one firing at a
time.** `/loop 20m /kit:ship-ticket unattended` is how you do that by hand, and
one ticket per firing is what keeps a park visible between firings rather than
buried in a run that kept going. #101 is the runner that does it without you.
