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
  `/kit:commit`" means the Skill tool, not an inlined copy of its steps.
- **Worktree-prefixed paths.** Once `prepare` creates the worktree, every
  Read/Edit/Write targets the path `kit:start-ticket` resolved. The tool cwd
  stays at the main checkout.
- **Never merge locally.** PRs merge on GitHub only.
- **Never run a test directory or the full suite.** Named files and examples
  only. Attended, widening needs an ask; unattended it is not yours to take. CI
  runs the full sweep on the PR.
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
| No plan present → invoke `/kit:design` | See below. |

`kit:start-ticket` `placement-check` skips itself when this skill is the caller,
and its `handoff` is a no-op here — `tdd` owns the placement check.

**Gate:** attended, do not start `tdd` until the user has accepted the plan.

### Unattended with no plan: design it, or park

**What makes the unattended path safe is the plan, not this file.** A ticket
reaching `tdd` has one — either a human wrote it and `/kit:triage` published it,
or this phase derived it because the ticket's kind says its acceptance can be
asserted without a human eye. Neither form is manufactured here. Where neither is
available, park.

**Only a ticket with no resolvable plan reaches this question.** The kind gates
where the plan comes from, never whether the ticket runs. A `user-experience`
ticket whose plan a human already settled is carried to a PR like any other kind:
the eye the kind exists to protect was present when it mattered.

The question is the ticket's kind: **can this ticket's acceptance be asserted
without a human eye?**

- **`bug`, `improve-codebase`, `technical-debt`** — invoke `/kit:design <number>
  unattended` and continue with the plan it stores. That mode owns what changes
  when nobody is watching; do not reproduce its rules here.
- **`user-experience`** — park, because no unattended pass may derive this
  ticket's plan. Say that the kind is why the plan could not be derived, and that
  designing it attended is what clears the park — after which every later firing
  carries it like any other kind.
- **No kind at all** — park. Unclassified is not a default, and choosing one here
  would be this skill granting itself the permission the label exists to give.

The acceptance criteria are what make the first case safe, not the kind label by
itself. `/kit:design`'s own preconditions require them, so a qualifying kind
whose body never says what "done" means parks there — correctly, and with a
better reason than this phase could give.

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
5. At sensible checkpoints, invoke `/kit:commit` via the Skill tool. Do not push
   from inside it.

**When the change adds or moves a class, run `kit:behavior-placement` first** —
model, value object, or service, and whether the app already derives the answer.
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
at triage, as `kit-hold`, which `/kit:new-pull-request` transcribes onto the PR.
A held PR gets its reviews and waits for the walkthrough; an unheld one was
decided not to need one.

Invoke `/kit:new-pull-request` via the Skill tool.

**If the plan was written by this run, say so in the PR body** — one line, that
the approach was designed unattended and the plan comment on the issue carries
the alternatives it beat. The reviewer is the first human to see that reasoning,
and a review that does not know it is reviewing a derived design reviews only the
diff.

**Verify the body carries `Closes #<issue>`.** `/kit:new-pull-request` adds it
when the branch starts with the issue number; the closing keyword in the *body*
is what closes the ticket, and the title prefix does not count. A missing keyword
strands every ticket whose `kit-blocked-by` marker names this one, because a
blocker reads as cleared only when its issue closes. `gh pr edit <n> --body` if
it is absent.

**Leave auto-merge off.** CI is fast and frequently goes green before the review
posts; `--auto` at creation time can merge the PR before anyone reviews it. The
CI gate sets it once the review round is closed.

---

## Phase 5 · `hand-off` — Leave the PR to CI

This skill ends at an open PR with auto-merge off, and that is the whole handoff:
nothing local picks it up, and there is nothing for the user to start.

Copilot posts its review a minute or so after `gh pr create`, and when CI
finishes, the project's `workflow_run` gate takes the PR from there — it calls
`/kit:review-copilot <N> unattended` to triage the findings and push the fixes,
then enables auto-merge unless something warrants attention. A PR carrying
`kit-hold` is skipped and waits for its walkthrough.

Waiting here for any of that would hold a session open for an indeterminate
stretch to watch work that needs nobody present.

Attended, tell the user:

> "PR #<N> is open with auto-merge off. Copilot reviews within a minute or two,
> and the CI gate triages and merges it from there — nothing to start."

Then stop. The worktree stays while the PR is open; the reclaim sweep at the top
of the next `/kit:ship-ticket` takes it once the PR has merged.

---

## Failure and interrupt handling

- **A phase fails** — the spec will not go green, a gate will not pass, the push
  is rejected. Stop at that phase and surface the state attended, park
  unattended. Never skip ahead.
- **The session is interrupted mid-phase.** The commits and the worktree leave
  the workspace recoverable. Resume by re-invoking the phase's own skill —
  `/kit:new-pull-request` picks up at `open-pr`.
- **Idempotent at phase boundaries.** Re-running the same issue after partial
  progress is safe: it detects the existing worktree and PR.
