---
name: start-ticket
description: Take a GitHub issue to a wired worktree with its plan verified — the clean-main check, the worktree off origin/main, the gitignored runtime files a fresh worktree lacks, and the qualification test that decides whether the approach is settled. Use when an orchestrator needs a ticket set up for implementation.
---

# Start Ticket

Take a GitHub issue to the point where implementation can begin: read it, create a worktree off `origin/main`, wire up what a fresh worktree lacks, and confirm the approach is settled.

**This is shared mechanism, not an entry point.** `kit:ticket-loop` invokes it as its first phase and carries the ticket further; running it alone stops at a wired worktree, which is strictly less. It is a skill rather than a command for that reason.

**Arguments:** $ARGUMENTS
The argument should be a GitHub issue number (e.g., `kit:start-ticket 42`) or a GitHub issue URL.

Each step below carries a stable id in backticks (`safety-check`, `wire-worktree`,
…). Those ids are the handle other commands reference — `/kit:ship-ticket` and
`kit:worktree-reclaim` both point at steps here. Renumber freely; **never rename an
id** without updating the references, and grep for one before you delete its step.

**Step 1 · `parse-issue` — Parse the issue reference:**
- Extract the issue number from `$ARGUMENTS`
- If no argument is provided, ask the user for the issue number

**Step 2 · `safety-check` — Safety check (run in parallel, from the main checkout):**
- `git status` — ensure the working tree is clean (no uncommitted changes)
- `git rev-parse --abbrev-ref HEAD` — note the current branch (`git branch --show-current` needs git ≥ 2.22 and fails on older installs)
- `git worktree list --porcelain` — check for an existing worktree whose branch carries this ticket-number prefix. Ask git rather than listing a directory: the layout may be the project's, not this suite's (see `worktree-layout` below).

If there are uncommitted changes, STOP and warn the user. Suggest they commit or stash first.

**If an existing worktree is found** (e.g. a worktree on branch `42-add-user-avatar`), present it to the user and ask:
> "A worktree for this ticket already exists: `42-add-user-avatar`. Resume it, or replace it with a fresh one?"

**Invariant: one worktree per issue.** Never create a second, suffix-differentiated sibling for the same issue number (e.g. `935-...-scope` alongside `935-...-fields`). Two live worktrees for one issue is a trap — the dev server can be booted in the stale one, hiding the real changes and reading as "my changes aren't showing." Enforce exactly one of:
- **Resume (default):** Skip `fetch-issue` through `wire-worktree`. Set `<branch-name>` to the existing branch and `<worktree>` to the path git reported, then jump to `worktree-paths` — use that path for all subsequent reads/edits. Do NOT re-run `wire-worktree` (the worktree is already provisioned). Take the lease on it as `create-worktree` describes: resuming is picking the worktree back up, and a stale lease from the pass that left it does not cover this one.
- **Replace:** Only if the existing worktree is being abandoned/re-scoped. First confirm it's not checked out elsewhere and has no unmerged work worth keeping (an open PR on its branch means keep it — Resume instead). Then `git worktree unlock <path>` — a reclaim holds a leased worktree however stale the ticket is, so re-scoping wedges against the previous pass's lease — and remove the old worktree by running `/kit:worktree-gc <branch>` **before** creating the new one. The new branch reuses the `<issue-number>-` prefix and may keep the same name — there is no sibling to collide with once the old one is gone.

**Step 3 · `fetch-issue` — Fetch the issue:**
- Run `gh issue view <number>` to read the full issue (title, body, labels, assignees)
- Summarize the issue for the user: title, key requirements, acceptance criteria if any

**Step 4 · `branching-strategy` — Decide the branching strategy:**
- **Default:** a new worktree off `origin/main` (proceed to `confirm-branch-name`).
- **Bundle onto current branch:** if the issue is a small follow-up to in-flight work on the current branch, ask the user whether to bundle. If yes, skip `confirm-branch-name` through `wire-worktree` and go straight to `worktree-paths` — no new worktree, no new branch.
- **Stack on a parent branch:** if the issue depends on an unmerged feature branch, ask whether to stack. If yes, replace `origin/main` with the parent branch name in `create-worktree`'s `git worktree add`.

**Step 5 · `confirm-branch-name` — Confirm the branch name:**
- Format: `<issue-number>-<short-description>` (e.g., `42-add-user-avatar`)
- Derive `<short-description>` from the issue title (lowercase, hyphens, max ~50 chars)
- Confirm with the user before creating

**Step 6 · `worktree-layout` — Find out who owns worktrees here:**

Run the `kit:worktree-conventions` skill. It answers three things, and the rest of
this command branches on them: whether the project has its own create command,
whether that command also provisions, and whether it has a matching remove
command.

Many projects do own this — a `just` recipe or `make` target that creates the
worktree *and* installs dependencies, links a dev proxy, writes local config.
Where one exists, `create-worktree` delegates to it and `wire-worktree` is
skipped entirely. Don't decide that here; the skill does.

**Step 7 · `create-worktree` — Create the worktree:**
- `git fetch origin main` — refresh `origin/main` (don't rely on "up to date" from `git status`; that only reflects the last fetch)
- **Project owns it:** run its create command, then resolve the resulting path with `git worktree list --porcelain` as the skill describes. Check the new branch's base — a project recipe often cuts from `HEAD` rather than `origin/main` — and offer a rebase if it's behind. Never assume the path; the command may not print it.
- **Otherwise:** `git worktree add .claude/worktrees/<branch-name> -b <branch-name> origin/main`, under this repo — never as a sibling of the main checkout.

Either way, hold the resulting absolute path as `<worktree>`. Everything downstream uses it.

**Then take the lease on it:**

```
git worktree lock --reason "kit:ship #<issue-number> since $(date -u +%Y-%m-%dT%H:%M:%SZ)" <worktree>
```

A worktree between commits is clean by construction, so another pass sweeping
concurrently sees no work to lose and reclaims this one out from under the pass
that owns it — which has already resolved paths and is writing against them.
A lock is how `kit:worktree-reclaim` already hears that somebody is in there, so
it holds the worktree instead.

The stamp is what makes it a **lease** rather than a hold nobody can release:
`worktree-reclaim.sh` expires a `kit:ship` reason after twelve hours, so a pass
that is killed mid-flight stops owning the worktree on its own. Write the reason
in exactly that shape — a lock in any other wording never expires, and one this
suite cannot date is held rather than reclaimed.

**Releasing it belongs to whoever took the ticket further.** `kit:ticket-loop`
does it when the pass ends. A worktree this command wired for someone working by
hand stays leased until they `git worktree unlock` it or the lease runs out.

**Step 8 · `wire-worktree` — Wire up the worktree:**

**If `worktree-layout` reported that the project's create command provisions,
skip everything below except the `plans/` link.** It already installed
dependencies and wired runtime files; symlinking on top of that replaces a real
`node_modules` with a link, which fails later and far from here. Say you skipped
it and why.

The `plans/` link is the exception. No project recipe knows this suite exists, so
nothing else will ever create it, and `plan-implementation` and `/kit:walkthrough`
both expect the cache to be there. Missing, the handoff no longer breaks — the
store is the issue, and `kit:ticket-artifacts` falls back to it — but every read
becomes a network call and every write splits across two directories.

A fresh worktree contains only tracked files. Anything gitignored but required
at runtime is missing, and the failures it causes are indirect — blank config,
a boot-time abort, a re-prompt — so wire these up before handing the worktree
over.

Resolve the main checkout once and reuse it, rather than hardcoding a path:

```
MAIN="$(git rev-parse --show-toplevel)"
WT="<worktree>"   # the path create-worktree resolved
```

**Symlink, don't copy.** A copy goes stale the moment the original rotates or
changes.

- **Secrets the app needs to boot.** Both halves of an encrypted-credentials
  setup must be linked — the ciphertext alone is useless without its key, and
  the symptom is silent: secrets read back blank and any task that asserts on
  one aborts at boot. In Rails that's:
  `ln -sf $MAIN/config/credentials.yml.enc $WT/config/credentials.yml.enc`
  `ln -sf $MAIN/config/master.key $WT/config/master.key`
  Adapt to whatever your stack keeps out of git (`.env`, `secrets.json`, …).
- **Claude permissions**, so the worktree inherits the main checkout's allowlist
  instead of re-prompting on rules you already approved:
  `ln -sf $MAIN/.claude/settings.local.json $WT/.claude/settings.local.json`
- **Installed dependencies.** Start with the project root — a fresh worktree has
  no `node_modules` at all, so the test runner isn't on disk and the first spec
  run dies with `command not found` rather than a failing test:
  `ln -sfn $MAIN/node_modules $WT/node_modules`
  Then any that live outside the root lockfile — local MCP server
  `node_modules`, vendored bundles — so servers come up green without a
  per-worktree install:
  `ln -sfn $MAIN/<path>/node_modules $WT/<path>/node_modules`
  Use `-n` on both, or a re-run links *inside* the existing directory instead of
  replacing it.
- **The shared `plans/` directory**, so the worktree reads and writes the same
  gitignored artifact cache as the main checkout. Without the link a fresh
  worktree has no `plans/` at all, so every artifact read costs a `gh` round trip
  and every artifact written lands somewhere the checkout can't see:
  `mkdir -p $MAIN/plans`
  `ln -sfn $MAIN/plans $WT/plans`
  Use `-n` so the link is created *as* `plans` rather than inside an existing
  directory. `plans/` is gitignored, so the symlink won't dirty the worktree.
- **Uploaded-file storage** is often wired by the project's own boot script. If
  yours does that, say so and let it — don't create the link yourself and risk
  conflicting with it.

**Step 9 · `worktree-paths` — Use worktree-prefixed paths from now on:**
- Every subsequent Read/Edit/Write must target `<worktree>/<file>` — the path `create-worktree` resolved, absolute. The tool cwd is still the main checkout.

**Step 10 · `plan-implementation` — Confirm the approach is already settled:**

What this step needs is a **plan** — the why, the chosen shape, and the
alternatives it beat. It does not care where that is stored, only that it exists
as something a reader can point at. Two forms count:

- **A stored plan**, read through `kit:ticket-artifacts` — the cache at
  `<worktree>/plans/<issue-number>-plan.md` if it's there, otherwise the marked
  `plan` comment on the issue, which the skill writes back to the cache as it
  reads. Never conclude there is no plan from a missing file: the file is the
  cache and the comment is the store, and a fresh clone, a rebuilt worktree, or
  another machine has the second without the first.
- **A plan written inline in the issue body**, under its own heading. Same
  artifact, carried in the body rather than a comment — a project that writes its
  tickets that way should not be made to produce a second copy. What makes it one
  is the same thing `/kit:triage` looks for: a block a reader can point at and say
  *this is the agreed approach and these are the alternatives it beat*.

**A body that merely reads as settled is not a plan.** Confidence, a named class,
a sentence about how it should work — that is an author's intent with nothing
recording what else was considered or why it lost, so nothing here can tell a
decision from a first guess. This test used to accept it, and the ticket that
passed was exactly the one where a choice nobody made got made inside a diff.
Absent a plan block, fall through to `/kit:design` below.

**Acceptance criteria are a separate requirement, not a substitute.** The body
must still state **testable acceptance criteria** and **what's out of scope** —
that is the done-ness contract, and the plan does not supply it. Judge it from
the body and comments `fetch-issue` already fetched; no extra lookups. Missing
either, say which and stop rather than inferring criteria from the plan: a
criterion you wrote is one nobody agreed to.

**The project's AFK-ready triage label (`ready-for-agent` in the canonical
vocabulary) is not part of that test.** A label is a claim about the artifacts;
the artifacts are the evidence, and the evidence is readable either way. Gating
on the label as well sends a fully designed issue back to `/kit:design` because
nobody applied a sticker — routine on projects where the same person files and
implements and never labels their own tickets. Read the label where it exists —
checking the project's own label mapping, since the canonical spelling is not the
only one — for the freshness dating below and as corroboration. Never withhold
qualification for its absence, and don't ask the user to go add it.

This is not in tension with `/kit:ship-ticket`, whose sweep *does* require the label
when it sweeps for startable tickets. There the label is a query filter over work
nobody asked for, and picking up an unlabelled issue would mean starting
something unbidden. Here a human has already named the issue, so the only
question left is whether the artifacts are there to read.

**`kit-blocked` is different, and worth saying out loud once.** It means a human
recorded something they must clear before this is started — a credential, a
vendor, a decision, a production reconcile. You are not gated on it here, since
naming the issue is a human overriding their own flag. But say it before writing
any code, quoting the reason from the body's "Blocked by" section, and let them
confirm. Never remove the label; that is their statement, not yours.

Length, formatting, and section headings are not the test. A three-paragraph plan
that names the rejected alternative qualifies; a long narrative that never made a
choice does not.

**If a plan block is inline in the body *and* a `plan` comment exists, the comment
wins** — it is the store, and the body is a copy of it. Say so rather than picking
silently; a genuine contradiction usually means the issue was re-scoped after the
plan was written, and that is worth a sentence to the user. (Cache-versus-comment
is a different question, and `kit:ticket-artifacts` settles it the same way.)

**If the plan is present**, read it and treat its *reasoning* as settled — the why, the chosen approach, the rejected alternatives, and the acceptance criteria. Do NOT relitigate those decisions or re-derive the approach from scratch; that's what the `/kit:design` session already did.
- After reading it, **ask the user before doing any verification work**: "Is this still fresh — written recently, and nothing relevant has changed in the codebase since?"
  - **Yes (fresh):** Skip the anchor-verification pass. Present a brief summary and ask whether to proceed or adjust — no file lookups needed.
  - **No (may be stale, or unsure):** Run the anchor-verification pass below.
- **Ask it for an issue too, and expect "no" more often.** An issue is *designed* to sit in the queue until someone picks it up — days or weeks — so an issue brief is stale by default in a way a plan written an hour ago is not. Date it from the most recent evidence the brief was still being maintained — the **later** of the AFK-ready label's application and the last substantive edit or comment, not whichever you find first. Not from when the issue was opened; that is the one date almost guaranteed to be wrong. Substantive means the brief itself moved: an edit to the acceptance criteria or scope, or a comment that changes them. A typo fix, a label shuffle, or a "bumping this" comment is activity, not maintenance, and dates nothing. Unlike the qualification test above, this step may cost a lookup — `updatedAt` and comment timestamps if `fetch-issue` didn't already carry them, and `gh issue view --json timelineItems` for when the label landed. Spend it only when the answer is in doubt.
- **Anchor-verification pass** (cheap and bounded — a handful of lookups, not a full re-exploration):
  1. Spot-check every concrete anchor it names — do those files/symbols still exist and look as described? (Targeted grep, or a symbol-lookup MCP tool such as Serena's `find_symbol` if one is available — grep alone is sufficient.)
  2. `git log` the touched area since it was written — did anything land that invalidates an assumption?
- **Decide:** anchors verify + no contradicting drift → present it as-is and proceed. An anchor is missing/moved, or drift contradicts an assumption → the intent still holds, but re-derive the map *in just the affected area* and flag the divergence to the user before proceeding.
- Note: the more concrete file/line detail an artifact asserts, the *more* verification it needs, not less — there's more surface to have gone stale. A well-written brief names interfaces and behavior rather than paths precisely so there is less to rot; verify what it *does* name.
- Present a summary and the verification result, then ask the user whether to proceed or adjust.

**If no plan is present**, do NOT improvise an ad-hoc plan and do NOT start implementing. The ticket has no settled approach yet, so the required next step is to **invoke the `/kit:design` skill** before proceeding.
- Run `/kit:design` with this issue number. The issue states the problem; `/kit:design`'s job is the *how* — placement, approaches, the grilling pass, and the durable handoff artifact.
- It stores the plan itself, via `kit:ticket-artifacts` — the marked comment on the issue plus the `$MAIN/plans/<issue-number>-plan.md` mirror. Don't write either file here.
- Once it's written, re-enter this step at the **"If the plan is present"** branch above: present the summary, run the anchor-verification pass, and ask the user whether to proceed or adjust before any implementation.
- **An unspecified issue is not a failure of the issue.** Falling through to here is the normal path for a ticket filed as a lean problem statement, which is how `/kit:architect` writes them. Don't report it as something missing or push the user to go back and rewrite the ticket.

**Step 11 · `placement-check` — Placement check (only if the work adds or moves a class):**

**If `kit:ticket-loop` invoked this command, skip this step
entirely.** Their implementation phase owns the placement check and runs it there,
next to the code being written — where a different answer can still change the
file cheaply. Running it here too just asks the same question twice, several gates
apart.

If the agreed approach introduces a new model, concern, service, or PORO — or
relocates behavior between them — run the `kit:behavior-placement` skill before
implementation starts. It answers where the behavior belongs (model → value
object → service) and whether the app already derives the answer somewhere.

Run it even when the settled approach already names a class. Both artifacts record
the *direction* — `/kit:architect` deliberately keeps the implementation substrate
out of tickets, and a good issue brief describes behavior rather than structure —
so a class name appearing in either is usually shorthand, not a verified placement
decision. This check is where it gets verified.

If the skill is installed per-project rather than globally, read it from the
worktree path (`$WT/.claude/skills/behavior-placement/`), not the main checkout.

**Step 12 · `handoff` — Hand off to implementation:**

This command stops here, with a wired worktree and an accepted plan. It writes no
code.

**If `kit:ticket-loop` invoked this command**, it is already
at its implementation step — say nothing about handoff and return. Do not suggest
re-invoking either; that restarts the caller from its first step.

**`kit:ticket-loop` unattended also overrides Step 10's questions**, since nobody is there to
answer them. It says which, and what each becomes. Follow its table over the
prose above when it is the caller.

**If the user ran this command directly**, they have taken the long way round.
`/kit:ship-ticket <issue>` runs these same steps and keeps going — worktree,
verification, TDD, simplify, PR — stopping at its gates, or at none of them with
a trailing `unattended`. Stopping at a wired worktree is a strictly smaller
outcome, so say so before reporting state.

Then tell them what they have:

> "Worktree `<worktree>` is ready on `<branch-name>`, plan accepted.
>
> `/kit:ship-ticket <issue-number>` takes it the rest of the way, stopping at
> its gates — add `unattended` and it stops at none of them. Either way it
> detects this worktree and resumes from implementation rather than recreating
> anything.
>
> Or implement here yourself, and reach for `/kit:commit` and
> `/kit:new-pull-request` when you're ready."

Either way, do not begin implementing. `placement-check` above is the last step
this command owns.


