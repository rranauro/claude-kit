# Why I built this

**Better designs, not faster typing.** `/kit:architect` and `/kit:design` are the
foundation — an argument with the model about the problem, and then about the
shape of the answer, before any code exists. What comes out is a design that's
easier to debug and needs less hand-holding, which is what makes it reasonable to
hand the coding to the model.

They're deliberately separate. A conversation that has somewhere to be stops
being a conversation: if every session ends in tickets, the model starts
narrowing options in turn two so a decision can be reached. `/kit:architect` is
allowed to end unresolved. `/kit:design` is where rigor is unconditional, and you
only enter it once you know what you're building.

`/kit:triage` is the same rigor applied to work that arrived instead of work you
started. It exists because of a specific failure: an issue can reach an agent
having never been grilled, and the decisions nobody asked about come back as
follow-up tickets. More than one follow-up per ticket doesn't converge. So triage
grills the *boundary* — which adjacent decisions this ticket forces but doesn't
settle — before `/kit:design` prices an approach against a scope that was never
examined. Once an approach exists, widening means re-pricing, so the question has
to be asked first or it doesn't get asked at all.

None of the three is the final word on scope. **The pass closest to
implementation wins:** architect draws the boundary with no code open, triage
grills it still with no code open, and `/kit:design` is the first one actually
reading what has to change — so if design finds the boundary in the wrong place,
it moves it. The price is that a widening is raised as its own question and
written back to the issue's acceptance criteria, so the PR still matches the
ticket it closes.

**Reviewing became the bottleneck.** Once construction got cheap, review was what
ate my time. GitHub is the substrate here, so the workflow automates that phase
where it can: the `pr-review-on-create` hook fires a review the moment a PR opens,
and `/kit:tend-prs` triages what comes back — on a loop, with nobody watching.

**Two models see different things.** Running more than one reviewer over the same
diff turns up bugs and inconsistencies uncannily well, and it happens before any
human reviewer engages. They stop requesting changes for things a bot would have
caught, and spend their attention on in-app testing instead.

## What the orchestration adds

Techniques are the easy part. Everything between them is where the workflow lives:

- **Sequence and gates.** `/kit:ship-ticket` is an orchestrator, not a technique. It
  knows the simplify pass runs *before* the PR exists, that auto-merge stays off
  until the first review round is answered, and that pushing waits for you. The
  ordering is the content — it's what stops you skipping the uncomfortable step
  because the code looks fine.
- **Handoff across a context boundary.** `/kit:design` stores a plan on the issue
  it belongs to, mirrored into a gitignored `plans/` cache that `kit:start-ticket`
  symlinks into every worktree, so the intended move is to converge, drop the
  plan, clear context, and run `kit:start-ticket` on it immediately — a clean
  window to implement in, against the repo the plan was written for. Storing it
  on the issue is what makes the boundary crossable by someone other than you:
  another machine, a scheduled run, a second developer, a worktree that has since
  been deleted. The store crosses that boundary rather than banking decisions: `kit:start-ticket` asks whether the plan is still fresh and, when
  it isn't, verifies the plan's anchors against the repo before proceeding. A plan
  that sat a week is a prescription written against code that has moved — the same
  argument that keeps solutions out of tickets.
- **Worktree plumbing.** `git worktree add` gives you a checkout missing every
  gitignored file the app needs to boot. `kit:start-ticket` wires those back up, and
  enforces one worktree per issue — two is a trap that hides your own changes.
- **Nothing to adopt.** No label vocabulary, no triage states, no `docs/agents/`
  config, no block written into your `CLAUDE.md`. These commands read issues and
  open PRs; how you triage, label, and run your process stays yours.
- **A review loop that distrusts reviewers.** `/kit:review-copilot` merges findings
  from multiple bots into one bucket per line and checks each claim against the
  actual code before acting on it — a "missing nil check" on a provably non-nil
  path gets classified and dropped, not applied. Every decision, including the
  rejections, lands in the commit body so the reasoning is durable in git rather
  than lost in a chat log. The second reviewer is coverage, not redundancy — and
  when two land on the same line independently, that corroboration is the
  strongest signal you get. Still a signal to verify, not a verdict: agreement
  makes a finding more likely to be real, never certain.

## The ideas behind it

Three opinions do most of the work here.

**Tickets should state the problem, not the solution.** `kit:writing-tickets` pushes
the outcome into vocabulary the app already has — not "output `data-field` names
are a superset of the input's," which sends someone off to write a parser, but
"the redesigned component must still declare every field the original declared,"
which sends them to the schema.

**Behavior decisions belong with the human, not the model.** Model, value object,
or service is a structural call you live with, so `kit:behavior-placement` hands you
the priority order and the smells that mean you got it wrong — the loudest being
a `Service.call(model:, …)` whose body mostly reads from `model`.

**Converging isn't the same as being right.** A design conversation converges on
whatever it drifted toward. `/kit:design` ends with an adversarial pass over the
agreed direction before the plan gets written, on the theory that the decision
nobody argued about is the one most likely to be wrong.
