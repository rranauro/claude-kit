---
model: sonnet
---

Pick up the next epic ticket whose blockers have all landed, and ship it.

**Arguments:** none.

Run it from the main checkout. This is a deliberate act — you invoke it when you
want a new implementation started, and you're around to review what comes back.

`/kit:tend-prs` is the janitorial half of the same workflow: it triages review
rounds, enables auto-merge, and cleans up merged worktrees, and never writes new
code. That split is the point. The janitor is safe to run unattended on a loop;
starting a ticket writes an implementation nobody has seen yet, so it stays a
thing you ask for.

---

## Step 1 · `select` — Find the startable ticket

Epic tickets filed by `kit:to-tickets` carry their blocking edges as a marker in
the issue body. This step reads them and finds work that is now unblocked.

```
gh issue list --state open --label ready-for-agent --json number,title,body,labels
```

A ticket is **startable** when all of these hold:

1. Its body contains `<!-- kit-blocked-by: ... -->`. No marker means it was not
   filed as part of an epic — leave it alone. This command never picks up an
   arbitrary `ready-for-agent` ticket, only one whose author declared its edges.

   **The label requirement here is deliberate, and is not the one
   `/kit:start-ticket` `plan-implementation` relaxed.** There a human has already
   named the issue, so the label merely corroborates a body you can read, and
   demanding it withholds work over a missing sticker. Here the label is the
   filter deciding what gets picked up at all, and dropping it would mean
   starting whatever happens to be open. Do not harmonize the two.
2. Every issue number in the marker is **closed**. `/kit:new-pull-request` writes
   `Closes #<issue>`, so a merged PR closes its ticket — a closed blocker means the
   work landed on `main`. An empty marker is trivially satisfied.
3. It does **not** carry the `kit-blocked` label — see below.
4. No open PR or live worktree already exists for it (it hasn't been started).

If several tickets are startable, take the lowest issue number. Filing order is
dependency order, so the lowest is the earliest slice.

**One ticket per invocation.** Not a safety bound — you asked for a ticket, and
this is the one. Run it again if you want the next.

If nothing is startable, say which tickets are waiting and on what, in one line
each, and stop. That report is the useful outcome: it tells you whether the epic
is blocked on a merge, on a person, or on nothing at all.

### `kit-blocked` — waiting on a person, not a merge

The marker in rule 2 carries one kind of edge: another ticket, cleared when a PR
merges and closes it. A machine clears it, which is why the loop can read it and
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

**Never apply this label, and never remove it.** Not to record that you skipped a
ticket, not because the reason reads as resolved, not because the blocking PR in
the other repo appears to have merged. Removing it is the human's statement that
the thing is actually cleared, and this command has no way to verify what it was
waiting on. Report the block; leave the label alone.

The reason lives in the issue body's `## Blocked by` section, alongside the
marker — the prose half of that section already exists for humans, and this is
what it is for. Read it and quote it when reporting, so the report says what is
being waited on rather than only that something is:

```
2 tickets are ready but blocked on a person: #52 (Stripe account still in
review), #58 (needs the production reconcile decided). Clear with
`gh issue edit <n> --remove-label kit-blocked`.
```

If a `kit-blocked` ticket has no reason in its body, say so — a block nobody can
read is indistinguishable from one left on by accident, and that is worth
surfacing rather than silently listing the number.

**Name the labelled tickets you skipped for want of a marker, separately.** A
ticket carrying the AFK-ready label but no `kit-blocked-by` line is the one
failure this command cannot distinguish from a deliberate omission — rule 1 says
leave it alone, and that is right, but from the outside it is indistinguishable
from being ignored for no reason. Someone briefed and labelled that ticket
expecting it to be picked up:

```
3 labelled tickets have no kit-blocked-by marker, so they are not startable
here: #41, #43, #47. Add `<!-- kit-blocked-by: -->` to make one startable now.
```

Report it as information, not an error, and never add the marker yourself — the
edges are a human's call, and an empty marker written by this command would be it
granting itself permission to start the ticket.

---

## Step 2 · `ship` — Hand it to the attended workflow

Invoke `/kit:ship-ticket <number>` via the Skill tool and let it run as written —
TDD, the placement check, the gates, `/simplify`, push, PR.

**Its human gates stay gates.** `read-plan` still shows you the brief and the
anchor-verification result before any code is written, and `push-and-pr` still
asks before pushing. Those questions were suppressed while this step lived inside
the unattended loop, and there was no one to answer them; here you are the one who
invoked the command, so answering them is cheap and the anchor check is exactly
what you want to see. If an anchor has moved or drift contradicts an assumption,
that is a design decision to make now, not a re-derivation to do silently.

From there `/kit:tend-prs` takes over: it catches the review round on the new PR,
triages the findings, enables auto-merge, and removes the worktree once it lands.
