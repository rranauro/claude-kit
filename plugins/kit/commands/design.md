---
model: opus
---

Design how to build something whose problem is already settled: compare approaches, pressure-test the choice, and write the durable plan.

**Arguments:** `$ARGUMENTS` — a GitHub issue number or URL, or a free-text
description of the work. A trailing `unattended` token runs the mode below.

## Precondition

The *what* is decided — by `/kit:architect`, by `/kit:triage`, or by the user
saying so. This skill answers *how*. If the problem itself is still open — if you
find yourself asking whether this is the right thing to build — stop and go back
to `/kit:architect`.

"Decided" includes a scope that `/kit:triage` just widened or narrowed. Start from
the scope your caller hands you, not the one the issue body was opened with.

**On scope, the default is the boundary you were handed.** `/kit:architect` set
it without the code open; `/kit:triage` grilled it with the code closed too. You
are the first pass reading what actually has to change, so you are the one who
can see the ticket is *unbuildable or wrong as written* — a decision this work
forces that the ticket leaves dangling, or scope the code shows is two things.
That is the test, and only that: not "is there a better boundary?", to which the
answer is nearly always yes.

Scale the exploration to the change. A one-file ticket does not get four
subsystems mapped.

A remark from the user about future work is **parked** — reported as a sentence
they can ignore. Never turn one into a scope question, and never present scope
options with `AskUserQuestion`: three options framed as a decision obligate a
decision that nobody asked for.

If the ticket really is unbuildable as written, the widening costs something
specific, so it has to be paid for:

- **Tell the user it got wider, as its own question.** Not folded into an
  approach comparison. They're agreeing to a bigger PR.
- **Write it back to the issue's acceptance criteria.** A widening changes the
  observable outcome, which is the one reason `kit:writing-tickets` allows a
  criterion to be revisited. Skip this and the PR stops matching the ticket it
  closes, and the reviewer can't tell agreed work from improvised work.
- **Prefer splitting to absorbing** when the extra scope stands on its own. Two
  reviewable tickets beat one PR that does two things.

Narrowing takes the same treatment. Silently building less than the criteria ask
for is the same defect wearing the other sign.

If the argument is an issue number or URL, read the issue first. It is the
statement of the problem; do not re-litigate it here.

## Unattended mode

`unattended` is passed by a caller that knows nobody is watching — today
`/kit:ship-ticket unattended`, reaching a ticket with no stored plan. **Never
infer it.** A
quiet session is not an absent user, and a design that decided rather than asked
is expensive to undo once it is the stored authorization.

Every step below still runs. What changes is that the two places this command
turns to the user — the incremental discussion in step 3, the confirmation in
step 4 — become a decision recorded in the plan, and the cases neither can settle
**park** rather than ask. Invoke the `kit:park` skill — it owns the stopping
shape, and a second one invented here would report differently for no reason.

### What has to be true before you design anything

Three preconditions. Any one missing, park without designing — say which:

1. **An issue.** A local plan file has no comment to store, no label to read, and
   nothing to park against.
2. **A kind saying acceptance is machine-assertable** — `bug`,
   `improve-codebase`, `technical-debt` in the canonical vocabulary. A
   `user-experience` ticket parks: its acceptance is someone looking at the
   result, and no unattended pass can stand in for that. **An absent kind parks
   too** — unclassified is not a default, and inferring one here would be this
   command granting itself the permission the label exists to give.
3. **Acceptance criteria in the body, and what is out of scope.** This is the
   load-bearing one. Attended, the user is what holds the design honest; here it
   is the criteria, and a design with nothing to be wrong against is not safer
   for having been unattended — it is only unreviewed.

### Where the human went

- **Step 3 decides instead of discussing.** Still 2-3 approaches, still scored on
  `kit:rails-codebase-design`, still carrying the `initialize` line and return
  types into the comparison. Then take the one the axis scores highest and write
  the comparison into the plan. Approaches that tie on the axis are the park
  below, not a coin toss.
- **Step 4's grilling becomes the park detector.** Run it exactly as written —
  state what the direction commits to — but answer each assertion against the
  acceptance criteria, the project's rules, and the code you read in step 1. Most
  resolve; that is the normal outcome and it is the same outcome attended. **An
  assertion that none of those three can settle is the interrupt.** This is the
  whole safety mechanism: the pass that existed to catch the decision nobody
  argued about now catches the decision nobody *can* argue about, because nobody
  is here.
- **Step 4's `kit:domain-modeling` handoff records, never writes.** A glossary
  entry or an ADR is a repository edit, and a term nobody argued is worse than no
  term. Note the candidate in the plan under its own heading and leave it for a
  human. The exception is a park: a design that has to **redefine or rename an
  existing glossary entry** is changing vocabulary other tickets are written in,
  and that is not yours.
- **Step 5 stores the plan the same way, and says how it was made.** Open the
  stored `plan` with `Designed unattended — the approach below was decided, not
  confirmed.` and keep a `## Decided without confirmation` section listing the
  choices a human would have been asked about. The plan is what authorizes
  implementation, so a reader has to be able to tell an authorization someone
  granted from one that was derived.
- **Nothing labels, and nothing asks.** No `ready-for-agent` — that is a human's
  claim that a ticket is safe to pick up, and this pass cannot make it. No
  `kit-hold` question, because there is nobody to answer it; leave the label as
  triage set it. No `kit-blocked-by` marker either, not even the empty form:
  `/kit:ship-ticket` refuses to write one for the reason that applies here too —
  writing it is granting yourself permission to start.

### Park on

- **Scope.** Widening, narrowing, or splitting all need the user's agreement when
  attended, and that requirement does not weaken because they are away.
- **A genuine either/or.** Two approaches the axis scores level, differing in
  something observable — a public interface, a migration's shape, what the user
  sees. Say what each commits to and let them pick.
- **A constraint the criteria do not bound.** Security, tenancy, anything
  destructive, a migration needing production reconciled. `kit:ticket-loop`
  already refuses these downstream; reaching one at design time is the earlier,
  cheaper stop.
- **A ticket that is unbuildable as written**, or criteria that turn out not to
  be testable once the code is open.

### Never park on

The absence of a preference. A passing remark about future work. A better
boundary you can see but the ticket does not need. "The user might want to weigh
in" — they might, always, which is why that is not a test. Park costs a human's
attention and this whole scheme is an argument that their attention is worth
spending on design; spending it on a decision the plan already answers is the
waste, and deciding silently to keep the run going is the failure the gates
existed to prevent.

## 1 — Ground

Read the code that will actually change, and the project's conventions
(`CLAUDE.md` first, then any `*_ARCHITECTURE.md`, ADRs, or design notes that bear
on this area). Cite `file:line`. Verify how things work — don't speculate.

Identify the constraints that genuinely bind here: security, tenancy,
performance, and the project's own rules.

## 2 — Place the behavior

Invoke the design skills the project keeps for this — at minimum
`kit:behavior-placement` (where the behavior belongs, and whether the app already
derives the answer) and `kit:rails-codebase-design` (what shape the result takes,
and what to count when it's wrong). Use whatever others the project has added.

`kit:behavior-placement` is a step: run its checks against every approach that
adds or moves a class. `kit:rails-codebase-design` is not a step — it is the
axis those approaches get scored on, so use its properties and counts exactly
when comparing. Neither one produces the design.

## 3 — Compare approaches

- Present 2-3 concrete approaches with trade-offs.
- For each: what changes, what's the blast radius, what are the risks?
- **For each approach that adds a class, carry step 2's output into the
  comparison — the `initialize` line and the return type of each public
  method.** Not a summary of them; the signatures. Approaches compared on
  features all look reasonable, and the difference between the shape that reads
  well in a year and the one that doesn't is usually visible only in what the
  constructor takes. Two approaches whose constructors are identical are one
  approach.
- Reference how similar problems are already solved in this codebase.
- Discuss incrementally. Don't dump everything at once — respond to the user's
  reactions. Unattended, there are none: decide on the axis and write the
  comparison into the plan.

## 4 — Confirm the choice

Once a direction emerges, invoke `kit:grilling` on it. A discussion converges on
whatever it drifted toward; this pass states what that direction commits to and
gets the user to confirm it, which is what catches the decision nobody actually
argued about. Do not skip it because the direction feels settled — that feeling
is the trigger. Most of what comes back should be confirmations; if it surfaces a
decision that genuinely changes performance, testability, or maintainability, go
back to step 3 for that branch.

Then invoke `kit:domain-modeling` on what the confirmed choice leaves behind —
but only if it left something. Two things qualify, and neither survives the plan
file:

- **The design names a concept the glossary doesn't have.** A class you are about
  to add is a noun the project will use in code review and in every later ticket.
  Write the entry now, while the meaning is still being argued; a term back-filled
  later records what got built rather than what was decided.
- **An approach was rejected for a reason a future reader would need.** Step 3
  compared 2-3 of them and the losers are about to disappear. If someone would
  credibly propose one again next quarter, that is an ADR. If they wouldn't, it
  isn't — the skill's three gates decide, not this step.

Most designs leave neither, and that is the normal outcome. Don't manufacture a
term or an ADR to have run the step.

## 5 — Write the plan

Summarize the agreed approach, what can be done incrementally vs. what requires a
big-bang change, and any open questions that must be answered before
implementation.

Then store it. `kit:ticket-artifacts` owns where it goes and how it is found
again; invoke it rather than reproducing the mechanics here.

### Where the plan goes

**There is an issue number:** store it as the `plan` artifact — the marked
comment on the issue, updated in place, and the `plans/<issue-number>-plan.md`
mirror. Both, in one step. This is the default now regardless of who invoked the
command: the same reasoning reaches an agent that never had your `plans/`
directory, and a direct invocation is no longer a plan that dies with the
machine.

The issue is already public, so posting there discloses nothing the ticket
didn't. What it does add is permanence — say what you're about to store before
you store it, and take a no. A conversation the user wanted to think in rather
than publish is theirs to keep local.

**There is no issue number:** write `plans/<short-slug>-plan.md` and stop.
Nothing to attach it to; don't offer to file an issue to hold it.

Keep it short. Capture the durable reasoning the lean issue intentionally omits —
the *why* behind the approach and the alternatives rejected — NOT file lists or
line numbers that will rot.

```markdown
# Issue #<number>: <title>

## Context & Motivation
[Why this matters, what prompted it]

## Agreed Approach
[The direction converged on — intent level]

## Key Decisions & Trade-offs
[Decisions made and why alternatives were rejected — the durable reasoning]
```

Only decisions that were actually examined belong in that last section — in
practice, the ones grilling put pressure on. A mechanism nobody argued about is
an assumption, and writing it beside genuine trade-offs launders it into one: the
implementer can't tell which line cost an hour of discussion and which was typed
in passing. Leave it out. If a substrate really does need naming, mark it
provisional and say what would change it.

Tell the user the plan will be picked up by `kit:start-ticket`. If you were
invoked by `/kit:triage`, say nothing about handoff and return — it has its own
publish step to finish, including the hold question below.

**When the plan lands on an issue and you were *not* invoked by `/kit:triage`,
check the issue carries a blocking-edge marker** — `<!-- kit-blocked-by: -->`,
empty if nothing blocks it, or with the comma-separated issue numbers that do.
Add it if absent; leave an existing one alone.

`/kit:ship-ticket` reads an absent marker as "not part of an epic, leave alone",
so a well-briefed labelled ticket without one is skipped silently and looks
startable the whole time. `/kit:triage` writes it in its own publish step, which
is why this is only for the standalone path — `kit:to-tickets` owns the format.

The marker takes issue numbers only. If the design surfaced a blocker no merge
will close — a credential, a vendor account, a change in another repo, a decision
left open — that goes on the issue as the `kit-blocked` label, with the reason in
the body's "Blocked by" section. `/kit:ship-ticket` skips a `kit-blocked` ticket
and reports the reason, so the ticket stays labelled and visible rather than
being withheld.

**Then ask whether the PR should be held:**

```
Hold the PR for in-app verification before it merges? (y/N)
```

If yes, `gh issue edit <n> --add-label kit-hold`. `/kit:new-pull-request`
transcribes it onto the PR, so the hold is in place before the CI gate can reach
it.

You have just spent a conversation on how this will be built, which is the most
informed anyone will be about whether the result needs *seeing* before it merges.
Waiting until the PR exists means racing a workflow run with the answer you
already had. Default to no — a bare Enter — and say yes when the approach you
just settled produces something you have to look at rather than something a test
asserts.

Only ask when there is an issue to label; a plan written to a local file has no
PR coming. In unattended mode, do not ask and do not answer — leave the label as
triage set it.

## Never

- Make implementation changes. This is design only.
- Re-open the problem statement. That's `/kit:architect`.
- Manufacture a scope decision out of a passing remark. Park it instead.
- Skip the grilling pass because the direction looks obvious.
- Enter unattended mode on your own reading of the session. A caller passes it.
