---
model: opus
---

Carry a ticket to an open PR unattended — worktree, verification, TDD, simplify,
push. Takes the tickets you name, or picks the next one whose blockers have all
landed.

**Arguments:** `$ARGUMENTS` — optional, and one of two kinds:

- **Issue numbers** (`/kit:run-ticket 612 613`) — take exactly those, in the order
  given. Selection is skipped.
- **A label** (`/kit:run-ticket bug`) — sweep as usual, but only over issues
  carrying it, and pick one the same way. Selection still happens; you have only
  narrowed what it may choose from.

With no arguments it sweeps the whole backlog. Every token digits means numbers;
a single non-numeric token is a label. **A mix of the two is a usage error** —
report it and stop rather than guessing which half was meant, since the two kinds
disagree about whether selection runs at all.

Run it from the main checkout.

**Naming tickets skips the selection, not the gates.** This command is unattended
either way — you are giving it a queue, not sitting down with it. The attended
single-ticket path is `/kit:ship-ticket`, which asks its questions because you are
there to answer them. Reach for that when you want to watch; reach for this when
you want to walk away.

**This command owns its path rather than delegating to `/kit:ship-ticket`.** That
command is the attended half of the same workflow and its value is its gates —
plan approval, push approval — which is exactly what cannot survive here. A gate
nobody can answer is a hang, and a gate answered by guessing is worse. So the
sequence is repeated here with each gate replaced by a rule, and the cases a rule
cannot decide **park** (see below) instead of asking.

**What makes that safe is the plan, not this file.** A ticket reaching Step 3 has
a plan — one a human wrote and `/kit:triage` published, or one Step 2 derived
because the ticket's kind says its acceptance can be asserted without a human
eye. `kit:start-ticket` no longer accepts a body that merely reads settled, and
neither form is manufactured here: the first is authorization granted, the second
is authorization the acceptance criteria and the PR reviewer stand behind. Where
neither is available, it parks.

`/kit:tend-prs` is the other unattended half: it picks up at the open PR, triages
the review round, enables auto-merge, and removes the worktree once it lands.
Between them, what is left for you is designing the tickets whose result someone
has to look at, answering the parks, and walking the PRs that carry `kit-hold`.

---

## Step 1 · `select` — Decide what to work

**With issue numbers given, that is the queue.** Selection is skipped entirely —
the label and marker rules below are query filters over work nobody asked for, and
you asked. Do not require `ready-for-agent`, and do not require a
`kit-blocked-by` marker.

Two checks still apply, because they are claims about the world rather than about
labelling:

- **`kit-blocked`** — skip the ticket and report the reason from its "Blocked by"
  section. Naming a ticket is not clearing the flag: a human overriding their own
  block does it while watching, and nobody is watching here.
- **An open blocker in its marker, if it has one** — skip and say which. The
  dependency has not landed, and that is true no matter who chose the ticket.

Report every skip by name, work the rest in the order given, and take each one
through Step 6 before starting the next. A park on one ticket does not stop the
queue.

**With a label, sweep as normal over the issues carrying it.** Add it to the
query — `gh issue list --state open --label ready-for-agent --label <given>` — and
apply every rule below unchanged. The label you passed is an **additional** filter,
never a substitute for `ready-for-agent`: that label is what says a human meant
this ticket for an agent, and no other label makes that claim. If nothing
survives, say so and name the label, so an empty result reads as "nothing matched"
rather than "nothing to do".

**With no arguments, sweep the whole backlog for one.**

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
   `kit:start-ticket` `plan-implementation` relaxed.** There a human has already
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

**One ticket per sweep**, labelled or not. Not a safety bound — you asked for a
ticket, and this is the one. Run it again if you want the next. Issue numbers are
the way to ask for several at once.

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

## The park

Every step below can reach a point where a human is genuinely needed. Nobody is
there. **Parking is what you do instead of asking** — it is this command's only
way to stop, and it is not a failure state.

To park a ticket:

1. Comment on the issue with what you found and what decision it needs. Say it in
   terms of the choice, not the symptom: *"the plan assumes `SiteAsset` owns the
   token table; it moved to `Css::TokenTable` in #1487 — does the approach still
   hold, or is the placement now different?"*
2. `gh issue edit <n> --add-label kit-blocked`, with the reason in the body's
   "Blocked by" section. This is the one place this command writes that label,
   and it is doing exactly what the label means: a human must clear it.
3. Leave the worktree and any commits in place. The next attempt resumes rather
   than rebuilds, and a parked ticket with its work-so-far on disk is worth more
   than a clean tree.
4. Report it in the final summary and stop working that ticket.

**Never guess to avoid parking, and never park to avoid thinking.** A ticket
parked over something the plan already answers wastes the interrupt this whole
scheme is trying to make rare; a decision made silently to keep the run going is
the failure the gates existed to prevent, arriving faster.

**Parking is durable state on GitHub.** Nothing needs to remember it, and no
scheduled pass has to re-derive it.

---

## Step 2 · `prepare` — Worktree and plan, unattended

Invoke `kit:start-ticket <number>` via the Skill tool for its mechanical half —
the clean-main check, the worktree, and the wiring. Those steps ask nothing.

**Its Step 10 gates are the ones this command overrides**, and each override
below replaces a question with a rule:

| Its gate | Here |
|---|---|
| "Is this still fresh?" | Don't ask — it documents how to date the plan (the later of the label's application and the last substantive edit). Derive it. |
| Skip the anchor pass when fresh | Run it **always**. It is a handful of lookups, and it is cheaper than a wrong implementation. |
| "Present a summary and ask whether to proceed or adjust" | The plan is the authorization. Anchors verify and no drift contradicts them → proceed. |
| An anchor moved, or drift contradicts an assumption | **Park.** Its own text calls this a design decision, and it is right. |
| `kit-blocked` present → confirm before coding | Unreachable: Step 1 rule 3 already filtered it. If you somehow got here, park. |
| No plan present → invoke `/kit:design` | Design it here when the kind allows, park when it doesn't — see below. |

### No plan: design it, or park

A stored plan is a human's authorization and this step spends it. Where there
isn't one, whether this command may make its own turns on a single question,
which the ticket's kind already answers: **can this ticket's acceptance be
asserted without a human eye?**

- **`bug`, `improve-codebase`, `technical-debt`** — invoke `/kit:design <number>
  unattended` and continue with the plan it stores. That mode owns what changes
  when nobody is watching; do not reproduce its rules here.
- **`user-experience`** — park, and say the kind is why. The plan is not what is
  missing: no unattended pass can stand in for someone looking at the result, so
  this ticket parks again on the next firing and the report should say so rather
  than reading as a fixable gap.
- **No kind at all** — park. Unclassified is not a default, and choosing one here
  would be this command granting itself the permission the label exists to give.

The criteria are what make the first case safe, not the kind label by itself.
`/kit:design`'s own preconditions require them, so a ticket with a qualifying
kind and a body that never says what "done" means parks there — correctly, and
with a better reason than this step could give.

**A park inside `/kit:design` is this ticket's park.** It has already commented
the decision and applied `kit-blocked`. Stop working the ticket, carry its reason
into Step 6's report, and **do not park it again** — a second comment says the
same thing twice and leaves a reader dating two copies of one reason.

**Skip the anchor pass for a plan produced by this run.** The row above says run
it always, and that is right for a plan that has aged in a queue. A plan written
minutes ago from the tree you are about to change has nothing to have drifted
from; re-verifying it against the source it was just read out of proves nothing.
Anchor-verify a stored plan, never a fresh one.

**What the reviewer is for.** A stored plan was argued with a human before any
code existed. A plan this step derived was not, and the acceptance criteria plus
the PR review are what stand in its place — which is why Step 5 says so on the
PR. That is the trade this path makes, and it is only a fair one while the
reviewer can see which kind of plan they are reading.

Also skip `placement-check` there — `implement` below runs it next to the code.

## Step 3 · `implement` — TDD

This is the work, and it is the same TDD loop `/kit:ship-ticket` describes; do
not invoke that command to get it. Its value is its gates, and a gate nobody can
answer is a hang.

Per requirement in the plan: extend the existing test for the surface you are
touching rather than adding a file (a new file is justified by a new production
unit, not by new behavior); write the test, run that single example and confirm
it fails, implement the minimal change, re-run, then run the broader test file
for regressions. Targeted runs need no permission; widening to a directory or the
full suite is not yours to take — CI does that on the PR.

Invoke `/kit:commit` at sensible checkpoints. If the project registers a
commit-time gate hook, expect to be blocked and to fix what it reports — that is
the gate working. **A gate you cannot satisfy after a genuine attempt is a park**,
not a thing to route around; the hook is a boundary somebody set on purpose.

When the change adds or moves a class, run `kit:behavior-placement` first. If it
lands somewhere the plan did not anticipate, that is not automatically a park —
the plan records direction, and placement is what this skill decides. Park only
when the answer contradicts something the plan actually argued.

Apply the project's own rules from `CLAUDE.md`. This command does not restate them.

**Park when the work will not converge.** A spec that will not go green after a
real attempt, a requirement the plan describes that the code cannot support, a
migration that needs production reconciled — write what you found and stop. An
implementation that fights the plan is telling you the plan was wrong, and that
is a human's to settle.

## Step 4 · `simplify` — Before the PR exists

Invoke `/simplify` on the working diff and commit what it applies. It runs here
because cleanups landing now become part of the original commits rather than
review-response commits, and because the automated reviewers that fire when the
PR opens hunt bugs, not duplication.

Do not run `/code-review` — opening the PR reviews this diff twice already.

**If `/simplify` proposes something that contradicts the plan, don't apply it and
don't park.** Note it in the PR body and move on. This pass tidies an
implementation; it does not relitigate a design, and a tidy-up is not worth
spending a human interrupt on.

## Step 5 · `open-pr` — Push and open the PR

Invoke `/kit:new-pull-request`. **There is no push gate here.** `/kit:ship-ticket`
asks before pushing so you can exercise the change in-app first; that question is
already answered — at triage, as `kit-hold`, which `/kit:new-pull-request`
transcribes onto the PR. A held PR gets its reviews and waits for your
walkthrough; an unheld one was decided not to need it.

**If the plan was written by this run, say so in the PR body** — one line, that
the approach was designed unattended and the plan comment on the issue carries
the alternatives it beat. The reviewer is the first human to see that reasoning,
and a review that does not know it is reviewing a derived design reviews only the
diff.

Verify the body carries `Closes #<issue>`. The closing keyword in the body is
what closes the ticket, and `/kit:run-ticket` reads a blocker as cleared only
when its issue is closed — a missing keyword strands every ticket downstream of
this one. `gh pr edit <n> --body` if it is absent.

Leave auto-merge off. `/kit:tend-prs` sets it after the review round is triaged.

## Step 6 · `report` — Say what happened

One paragraph. Which ticket was taken, what the PR number is, whether the plan
was stored or designed by this run, whether it carries `kit-hold` and so needs
your walkthrough, and — separately and by name — anything parked, with the
decision each one is waiting on. The parked list is the useful half of this
report: it is your queue.

**Split the parked list by what would clear it.** A ticket parked on a decision
inside its design is waiting on an answer. A `user-experience` ticket parked for
its kind is waiting on you to run `/kit:design` yourself, and will park on every
firing until you do. An unclassified one is waiting on a label, which is seconds
of work. Reported as one list they read as the same problem and the cheapest of
the three hides among the others.

From here `/kit:tend-prs` takes over — it catches the review round, triages the
findings, enables auto-merge unless something warrants your attention, and removes
the worktree once GitHub merges.

**A sweep still takes one ticket per firing**, and a label narrows a sweep rather
than turning it into one. Running the whole ticket unattended does not make either
form a batch. `/loop` over this command is how you
work the backlog, and one ticket per firing is what keeps a park visible between
firings rather than buried in a run that kept going. Explicit arguments are the
exception, and they are bounded by the list you typed.
