---
name: ticket-loop
description: Carry one named ticket from a wired worktree to an open PR — prepare, TDD, simplify, push — attended with gates you answer, or unattended with each gate replaced by a rule and a park where no rule decides. Use when a command has chosen a ticket and needs it implemented.
---

# Ticket Loop

One ticket, from the issue to an open PR. `/kit:ship-ticket` invokes this after
it has decided which ticket; everything downstream of the open PR belongs to the
CI gate the consuming project runs on `workflow_run`.

**This is shared mechanism, not an entry point.** It takes a ticket someone else
selected and it stops at an open PR — strictly less than the command that invokes
it. Its phase ids (`prepare`, `tdd`, `simplify`, `open-pr`, `hand-off`) are the
handle other commands reference when they re-enter partway.

**Arguments:** an issue number, and a mode — `attended` or `unattended`.

## The mode is the whole difference

Attended and unattended run the same five phases in the same order. One
substitution separates them, and it is stated here once rather than in each
phase:

> **A gate is a question when attended. Unattended it is a rule, and where no
> rule decides, a `kit:park`.**

That is why there is one loop rather than two. A gate nobody can answer is a
hang; a gate answered by guessing is worse than either.

**Never infer `unattended`.** A quiet session is not an absent user. The caller
passes it because it knows nobody is watching.

Each phase below states its gate, then the rule that stands in for it. Where a
rule cannot decide, invoke `kit:park` — that skill owns the stopping shape, and
this one does not restate it.

## Mandatory constraints, both modes

- **Do not duplicate constituent skill bodies.** A phase saying "invoke
  `kit:commit`" means the Skill tool, under the name the tool takes — no leading
  slash — and not an inlined copy of its steps, nor a read of the command file.
  `docs/commands.md` says why the file read fails.
- **Worktree-prefixed paths.** Once `prepare` creates the worktree, every
  Read/Edit/Write targets the path `kit:start-ticket` resolved. The tool cwd
  stays at the main checkout.
- **Never merge locally, and never bring the base into the branch at all.** The
  PR merges on GitHub, through the auto-merge `hand-off` arms. Integrating
  `main` *into* the branch is a different act and equally not a pass's: `git
  merge`, `git rebase` and `gh pr update-branch` are one operation under three
  names, and a PR that has fallen behind its base is the operator's to carry
  forward. A pass that integrates has moved the head its review round was
  decided against.
- **A denied operation stays denied however it is spelled.** The grant denies
  operations rather than commands, so a command the deny list never named that
  produces a denied command's effect is denied too — `gh api` alone can merge a
  branch. This holds in **every permission mode**, and the mode it is written
  for is auto: a session whose launcher never pinned the mode prompts for
  nothing, so a deny entry is the only thing left refusing anything. Do not read
  a command that went through as a command that was allowed. Reaching a denied
  operation is a `kit:park`, never a thing to accomplish another way.
- **Never run a test directory or the full suite.** Named files and examples
  only. Attended, widening needs an ask; unattended it is not yours to take.
  No phase is exempt: CI is the merge gate, so nothing here runs the suite to
  decide whether a PR may leave draft either. The one carve-out is the
  project's declared ship gate, `hand-off` step 4.
- **Apply the project's own rules from `CLAUDE.md`.** This skill does not restate
  them.

---

## Phase 1 · `prepare` — Worktree and plan

Invoke `kit:start-ticket <number>` via the Skill tool. Its mechanical half — the
clean-main check, the worktree off `origin/main`, the branch name, the gitignored
runtime wiring — asks nothing and runs identically in both modes.

Its Step 10 is the gate. Attended, answer its questions as written: is the plan
still fresh, its anchor-verification pass when it is not, then the summary and
"proceed or adjust". Do not improvise a plan, do not require a stored plan when
the issue already says what a plan would, and do not read `plans/` directly — a
missing file is not a missing plan; `kit:ticket-artifacts` resolves it.

Unattended, each of those becomes a rule:

| Its gate | Unattended |
|---|---|
| "Is this still fresh?" | Don't ask — it documents how to date the plan (the later of the label's application and the last substantive edit). Derive it. |
| Skip the anchor pass when fresh | Run it **always**. A handful of lookups, cheaper than a wrong implementation. |
| "Present a summary and ask whether to proceed" | The plan is the authorization. Anchors verify and no drift contradicts them → proceed. |
| An anchor moved, or drift contradicts an assumption | **Park.** Its own text calls this a design decision, and it is right. |
| `kit-blocked` present → confirm before coding | Park. The selection step should have filtered it. |
| Criteria or out-of-scope missing → "say which and stop" | **Park**, naming which, in those words — a stop nobody reads records nothing. With no plan, don't stop here at all: `/kit:design` checks the same precondition and parks on it. |
| No plan present → invoke `kit:design` | See below. |

`kit:start-ticket` `placement-check` skips itself when this skill is the caller,
and its `handoff` is a no-op here — `tdd` owns the placement check.

**Gate:** attended, do not start `tdd` until the user has accepted the plan.

### Unattended with no plan: design it, or park

**What makes the unattended path safe is the plan, not this file.** A ticket
reaching `tdd` has one — either a human wrote it and `/kit:triage` published it,
or `/kit:design` derived it against the ticket's acceptance criteria. Neither
form is manufactured here. Where neither is available, park.

**Only a ticket with no resolvable plan reaches this question, and it has one
answer whatever the kind:** invoke `kit:design` through the Skill tool with
`<number> unattended`, and continue with the plan it stores. That mode owns what
changes when nobody is watching and the preconditions it parks on; do not
reproduce either here.

**The kind decides whether the PR is held, never whether the ticket runs** —
`hand-off` step 3. A plan a human settled is not held for its kind, because the
eye the kind exists to protect was present when it mattered.

**Skip the anchor pass for a plan produced by this run.** The table says run it
always, and that is right for a plan that has aged in a queue. A plan written
minutes ago from the tree you are about to change has nothing to have drifted
from. Anchor-verify a stored plan, never a fresh one.

**What the reviewer is for.** A stored plan was argued with a human before any
code existed. A plan this phase derived was not, and the acceptance criteria plus
the PR review stand in its place — which is why `open-pr` says so on the PR. That
trade is only fair while the reviewer can see which kind of plan they are
reading.

---

## Phase 2 · `tdd` — Test-first implementation

Not delegated — this is the work itself. Identical in both modes; there is no
gate here, only the convergence rule at the end.

Use the project's own test framework and layout — read them from `CLAUDE.md`, the
manifest, or CI config rather than assuming. The Rails/RSpec form below is the
worked example; substitute the equivalent for your stack.

**Test placement — extend before adding.** For each requirement in the plan, find
the existing test covering the surface you are touching:

- Modifying an existing method → extend its existing test file. A new group, not
  a new file. *(Rails: `spec/<type>/<name>_spec.rb`, a new `describe`/`context`.)*
- Adding a public method to an existing class → same; a new group for that method
  in the existing file.
- Adding a brand-new unit (class, module, component) → a matching new test file.
  The new file is justified by the new production unit, not by new behavior.
- Cross-cutting, with no obvious owner → attended, ask where the test belongs.
  Unattended, put it with the surface the plan names first.

Then, per requirement:

1. Write the test in the file selected above.
2. Run that single example and confirm it fails as expected. Targeted runs need
   no permission. *(Rails: `bundle exec rspec <path>:<line>`.)*
3. Implement the minimal change. Re-run the example; confirm green.
4. Run the broader test file for regressions. Naming another *file* is fine;
   widening to its directory is not.
5. At sensible checkpoints, invoke `kit:commit` via the Skill tool. Do not push
   from inside it.

**When the change adds or moves a class, run `kit:behavior-placement` first** —
model, domain object, or service, and whether the app already derives the answer.
If it lands somewhere the plan did not anticipate, that is not automatically a
stop: the plan records direction, and placement is what that skill decides. Stop
only when the answer contradicts something the plan actually argued.

**If the project registers a commit-time gate hook, expect `/kit:commit` to be
blocked and to fix what it reports** — that is the gate working. A gate you
cannot satisfy after a genuine attempt is a stop, not a thing to route around;
the hook is a boundary somebody set on purpose.

**When the work will not converge** — a spec that will not go green after a real
attempt, a requirement the code cannot support, a migration needing production
reconciled — attended, surface it and stop. Unattended, park: an implementation
fighting the plan is telling you the plan was wrong, and that is a human's to
settle.

---

## Phase 3 · `simplify` — Before the PR exists

Specs are green; the PR is not open yet. Invoke `/simplify` via the Skill tool on
the working diff and commit what it applies.

It runs **here, not later**, because cleanups landing now become part of the
original commits rather than review-response commits — and because the automated
reviewers that fire when the PR opens hunt bugs, not duplication. Reuse,
over-abstraction, and altitude problems are exactly what they under-report.

Do **not** run `/code-review`. Opening the PR reviews this diff twice already
(Copilot plus the Claude headless hook); a third bug-hunt over the same lines
buys nothing. `/simplify` is quality-only, which is why it does not overlap.

**If `/simplify` proposes something that contradicts the plan**, attended,
surface it rather than applying it. Unattended, don't apply it and don't park —
note it in the PR body and move on. This pass tidies an implementation; it does
not relitigate a design, and a tidy-up is not worth a human interrupt.

---

## Phase 4 · `open-pr` — Push and open the PR

**The gate is the push.** Attended, ask:

> "Ready to push and open the PR, or do you want to boot the worktree and
> exercise the change in-app first?"

If they want to test first, offer `/kit:walkthrough <issue>`, which derives a
checklist from the AC and the diff and keeps its position on disk. If they would
rather drive unaided, pause. If they approve, continue.

**Unattended there is no push gate**, because the question is already answered —
at triage, as `kit-hold`, which `/kit:new-pull-request` transcribes onto the PR,
or by the plan and the kind, which `hand-off` step 3 reads. A held PR gets its
reviews and waits for the walkthrough; an unheld one was decided not to need one.

Invoke `kit:new-pull-request` via the Skill tool with `draft`, adding `unattended`
when this pass is. The `draft` token is what makes `hand-off` possible: a draft
PR still runs CI and still gets both reviews, but cannot merge out from under the
round this pass is about to close. `unattended` is what lets the body be written
without stopping for a question nobody is there to answer.

**If the plan was written by this run, the PR body says so in its Gist.**
`kit:visual-pr` writes that line when the issue's `plan` comment opens with
`/kit:design`'s unattended line; confirm it is there. The reviewer is the first
human to see that reasoning, and a review that does not know it is reviewing a
derived design reviews only the diff.

**Verify the body names the issue with `Closes` or `Part of`.**
`/kit:new-pull-request` writes `Closes #<issue>` when the diff satisfies it; the
closing keyword in the *body* is what closes the ticket, and the title prefix does not count. A missing keyword
strands every ticket whose `kit-blocked-by` marker names this one, because a
blocker reads as cleared only when its issue closes. `gh pr edit <n> --body` to
add `Closes` if it carries neither. Leave a `Part of` in place — a `Closes`
written over it closes an unfinished issue.

---

## Phase 5 · `hand-off` — Close the review round, then leave the PR to CI

The PR is open as a draft. Both automated reviews are addressed here, in the
worktree that already holds the plan and the implementing context, so the PR
leaves draft already reviewed, and CI carries it to merge from there.

**Do not release the lease yet.** This phase writes fixes in the worktree; a
sweep reclaiming it mid-write is exactly what the lease prevents. The unlock is
the last step below.

**1 · Wait for the reviews the project runs.** Look for a `## Review sources`
section in the project's `CLAUDE.md`, read as step 4 reads `## Ship gate`:

```markdown
## Review sources
- copilot
```

The names are `copilot` and `claude-review`. Pass what it lists, comma-joined;
absent, pass nothing and both are expected.

```
plugins/kit/scripts/await-reviews.sh <pr-number> [--sources <listed>]
```

It waits for CI to complete, requests the Copilot review, then blocks until
every declared source — that review, the `<!-- claude-pr-review -->` marker —
has landed or its ceiling expires. The ordering is the platform's, not a
preference — the script's header says why, and it is not reproducible by hand.

Its last two lines name any declared source that did not arrive (`missing:`)
and any the project does not run (`not run:`). **Carry on with what landed, and
say which was missing and which was not run** wherever this phase reports. A
silent partial collation is worse than a slow one, and a timed-out source is not
an escalation.

**When the wait returns, check `<worktree>` is still on disk, and stop if it is
not.** This is the one step with real time on both sides of it, so it is where a
sweep elsewhere can have reclaimed the checkout — and every step below writes in
it. A pass that carries on regardless fixes nothing, signs off nothing, and
leaves the PR in draft with no record of why. Attended, say the worktree is gone
and stop. Unattended, `kit:park` on it, naming the PR number so the round can be
resumed: the bin is **waiting on the world**, since nothing about the ticket
changed and what has to happen is a later pass rebuilding the checkout. Either
way the lease went with the directory, so there is nothing to unlock.

Pass `--no-request` where the project still has automatic Copilot review
enabled; asking as well yields two reviews, the second landing after this round
has closed.

**2 · Collate and address them.** Invoke `kit:review-copilot` via the Skill tool
with the PR number, against the local branch. It triages both sources and pushes
what it fixes; that push is its own and this phase is built around it, not
against it.

**3 · Judge the diff's shape.** Invoke `kit:shape-review <pr-number>` through
the **Agent tool**, so its inventory stays out of this session, and **wait for
it to return** — the Agent tool returns when the work is launched, so reading its
answer early takes the failed branch below and arms a PR the review would have
held. Its final message is the comment, opening on `<!-- kit-shape-review -->`.

It runs here because the round's fixes are pushed, so it judges the head that
will merge (it pushes nothing itself), and auto-merge is not yet armed, so a hold
cannot lose a race with a green CI.

- **`**No shape findings.**`** — post nothing and carry on to step 4.
- **No marked comment comes back** — the pass failed. Say so wherever this phase
  reports and carry on as if clean: a hold with no review to give its reason is
  worse than leaving the shape unjudged.
- **Findings, attended** — show them and ask whether to post the review and hold
  the PR, or post it and arm auto-merge anyway, or post it, hold it, and reshape
  now. Never hold without saying so. The third answer is the first one followed
  by invoking `kit:reshape <pr-number>` through the Skill tool, here, before
  step 4 — it pushes, and step 4 has to attest the head it leaves.
- **Findings, unattended** — hold it, record first:

  ```
  gh pr comment <pr-number> --body-file <the comment>
  gh pr edit <pr-number> --add-label kit-hold     # only if the comment posted
  ```

  `docs/labels.md` is the rule. A held PR still runs step 4, but step 5 is
  `gh pr ready <pr-number>` alone — **no auto-merge**, and so no snapshot and no
  poll, which exist only to time the arming.

  If either write fails, the PR **stays in draft** — skip to step 6, report
  which write failed, and say this pass's hold is not in place — a `kit-hold`
  transcribed from triage is still there if it was. A draft cannot merge, and it
  is the one hold left when the label is not there to carry it.

**Then hold it for its kind, if its plan was derived.** Two facts `prepare`
already has, so look neither up again: the plan it resolved opens with
`/kit:design`'s `Designed unattended` line, and the issue's labels carry none of
`bug`, `enhancement`, `improve-codebase`, `technical-debt`. Both true means
nobody has looked at a result whose acceptance is someone looking. It is the
plan's line that decides, not whether this run designed it: a firing that
resumes a stored derived plan owes the same hold.

Hold it exactly as a shape finding is held — asked attended, record first
unattended, the same failure path — with this as the comment:

```
Held: the plan was designed unattended and this ticket's kind (<kind, or none>) needs someone to look at the result before it merges.
```

Where the shape hold already applied `kit-hold`, post the comment and skip the
label write.

**4 · Run the project's ship gate, if it declares one.** Look for a `## Ship
gate` section in the project's `CLAUDE.md`, read as `kit:worktree-conventions`
reads `## Worktrees`:

```markdown
## Ship gate
- run: `bin/ci`
```

Absent, skip to step 5. Present, run that command once, from `<worktree>`, after
step 2's push — a gate that posts a status attests the SHA it ran on, so a run
before the round's last push signs off a head the PR no longer has. Do not commit
or push between this run and step 5 for the same reason.

**Non-zero keeps the PR in draft.** Skip step 5 and go to step 6. Attended, surface the failing output and stop.
Unattended, park on the failing step; a denied permission is a failure too, and
names the grant the operator's project settings lack.

**5 · Mark it ready, then arm auto-merge once the transition's run has
registered.**

```
sha=$(gh pr view <pr-number> --json headRefOid -q .headRefOid)
gh api repos/{owner}/{repo}/commits/$sha/check-runs --jq '.check_runs[].id'
gh pr ready <pr-number>
# poll that same call until an id appears the first one did not report, to 120s
gh pr merge <pr-number> --auto --squash
```

**Arming before the run registers merges the PR against the draft's checks.**
Marking ready leaves a context already green on the head SHA green, so where a
project reports the same required contexts for a draft that it does for a ready
PR — the common shape, since skipping the expensive steps on a draft leaves the
context's *name* intact — auto-merge evaluates as satisfied the moment it is
armed, and GitHub merges in the seconds before the `ready_for_review` run creates
its first check run.

**The wait is for the run to register, never for it to finish.** One queued check
run is enough to leave the required contexts unsatisfied, and auto-merge holds
the PR from there — so this costs the seconds GitHub takes to schedule a run,
not a CI round.

**The snapshot is what makes the poll unambiguous.** `/kit:review-copilot` pushed
its fixes at step 2 and started a run of its own, so a poll asking merely whether
anything is pending can be answered by that run and arm against one the
transition never triggered.

**Arm anyway when 120s passes with no new id**, and say so wherever this phase
reports. A project that reports nothing on the transition is describing its own
CI rather than failing here.

**Skip the snapshot and the poll where the project declares that drafts run the
full checks.** Look for a `## Draft checks` section in the project's
`CLAUDE.md`, read as step 4 reads `## Ship gate`:

```markdown
## Draft checks
- full
```

`full` says every required check a draft passes is the same check a ready PR
would run, so the head's green is already the verdict and there is no
transition run to wait for. Mark ready and arm in the same breath. Absent, or
any other value, poll as above: the wait is cheap, and arming early on a project
that skips steps on drafts merges a PR its full CI never saw.

**The arming above consults no label** — only step 3's outcome, which withholds
it from a PR this pass held. A `kit-hold` set at triage is not special-cased
here, and that is only safe where the consuming project enforces the hold as a
**required check** — a held PR then cannot merge however auto-merge is set, so
the label stops depending on any pass reading it in time. **A project without
that check must not adopt this step**: there, auto-merge armed on a held PR
merges it, which is the thing the hold was set to prevent.

**Arming is this pass's last act on the PR, in both modes.** Step 6 releases the
lease and reports, and nothing between here and the end of the pass writes to the
PR again — no second `gh pr merge`, no `gh pr edit`, no comment, no push. The
operator owns the PR from this line onward.

**So a disable stands.** An operator who runs `gh pr merge <N> --disable-auto`
while this pass is still running has made the decision that holds, and it holds
because nothing here re-arms rather than because something here recognises it.
The pass runs `gh` as the operator, so the PR's timeline cannot attribute the
disable to anyone — which means a pass finding auto-merge off can never tell its
own branch update from a person's deliberate hold, and must not guess. Treating
one as the other is how a pass merges a PR over the hold an operator had just
placed on it.

**And a check that goes red after arming is not this pass's to repair.** Step 4's
gate ran before the PR left draft; a failure after that is a red PR, which is
visible to the operator without anything here acting on it.
`docs/tending-on-a-runner.md` says the same of the runner, for the same reason.

**6 · Release the lease, then report the PR as you find it:** `git worktree
unlock <worktree>`. The pass is over, so the worktree is an ordinary sweep
candidate again and the next `/kit:ship-ticket` reclaims it once the PR merges.

**Then read the PR once.** Having armed auto-merge is not evidence that it is on:

```
gh pr view <pr-number> --json state,autoMergeRequest,statusCheckRollup
```

**Report both as found wherever this phase reports** — the auto-merge state, and
any failing check the rollup names — attended in the line below, unattended in
the report `/kit:ship-ticket` Step 3 writes. Where auto-merge comes back off
after step 5 armed it — and the PR is not already merged, which also reads as
off when the checks were green at arming — say so and say the pass did not re-arm: that line is the
only record an operator has that their disable survived the rest of the pass,
and a pass asserting "auto-merge on" from its own arming reports a state the PR
may not be in.

Attended, tell the user:

> "PR #<N> is open, reviewed, and ready, and auto-merge reads on — <the
> transition's run registered, so the merge waits on it | nothing new registered
> within 120s, so the merge waits on the checks already on the commit | the
> project declares draft checks full, so it armed without waiting>. <Any
> failing check the rollup named.> <Which declared review source, if any, did
> not arrive, and which the project does not run.>"

or, where it reads off:

> "PR #<N> is open, reviewed, and ready, but auto-merge reads off — this pass
> armed it and did not re-arm it, so nothing here will merge the PR. <Any failing
> check the rollup named.> <Which declared review source, if any, did not
> arrive, and which the project does not run.>"

or, when step 3 held it:

> "PR #<N> is open, reviewed, ready and held (`kit-hold`) — <the shape review
> posted on it is the reason, and `/kit:reshape <N>` offers an in-flight reshape
> on this branch, or a ticket blocked on it | the kind comment posted on it is the reason>, and auto-merge
> is not armed."

Unattended, the same line goes in the report `/kit:ship-ticket` Step 3 writes.
Drop the `/kit:reshape` clause where the third answer already ran it.

Then stop. Nothing local picks it up from here.

---

## Failure and interrupt handling

- **A phase fails** — the spec will not go green, a gate will not pass, the push
  is rejected. Stop at that phase and surface the state attended, park
  unattended. Never skip ahead.
- **However the pass ends, release the lease** — `git worktree unlock
  <worktree>` — including on a park. `kit:park` leaves the worktree and its
  commits in place, and the commits are what survive a later reclaim; holding the
  directory as well would leave a worktree no sweep can ever take. A resumed pass
  takes the lease again in `prepare`.
- **The session is interrupted mid-phase.** The commits and the worktree leave
  the workspace recoverable. Resume by re-invoking the phase's own skill —
  `/kit:new-pull-request` picks up at `open-pr`.
- **Idempotent at phase boundaries.** Re-running the same issue after partial
  progress is safe: it detects the existing worktree and PR.
