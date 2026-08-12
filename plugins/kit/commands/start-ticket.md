---
model: sonnet
---

Start work on a GitHub issue by reading it, creating a worktree off `origin/main`, and planning the implementation.

**Arguments:** $ARGUMENTS
The argument should be a GitHub issue number (e.g., `/kit:start-ticket 42`) or a GitHub issue URL.

Each step below carries a stable id in backticks (`safety-check`, `wire-worktree`,
…). Those ids are the handle other commands reference — `/kit:ship-ticket` and
`/kit:cleanup-worktree` both point at steps here. Renumber freely; **never rename an
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
- **Resume (default):** Skip `fetch-issue` through `wire-worktree`. Set `<branch-name>` to the existing branch and `<worktree>` to the path git reported, then jump to `worktree-paths` — use that path for all subsequent reads/edits. Do NOT re-run `wire-worktree` (the worktree is already provisioned).
- **Replace:** Only if the existing worktree is being abandoned/re-scoped. First confirm it's not checked out elsewhere and has no unmerged work worth keeping (an open PR on its branch means keep it — Resume instead). Then remove the old worktree per `/kit:cleanup-worktree` semantics (`git worktree remove [--force]`, sweep the path) **before** creating the new one. The new branch reuses the `<issue-number>-` prefix and may keep the same name — there is no sibling to collide with once the old one is gone.

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

**Step 8 · `wire-worktree` — Wire up the worktree:**

**If `worktree-layout` reported that the project's create command provisions,
skip everything below except the `plans/` link.** It already installed
dependencies and wired runtime files; symlinking on top of that replaces a real
`node_modules` with a link, which fails later and far from here. Say you skipped
it and why.

The `plans/` link is the exception, and it is not optional. No project recipe
knows this suite exists, so nothing else will ever create it — and without it
`plan-implementation` finds no plan and `/kit:design`'s handoff silently breaks.

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
- **The shared `plans/` directory**, so the worktree sees the same persistent,
  gitignored plan store as the main checkout. This is how `/kit:design`'s
  `plans/<n>-plan.md` reaches `plan-implementation` — without the link a fresh
  worktree has no `plans/` at all and the handoff silently breaks:
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

What this step needs is a **settled approach** — the why, the chosen shape, the
rejected alternatives, and how you'll know it's done. It does not care which of
two artifacts carries that. Take whichever you have:

- **A plan file** at `<worktree>/plans/<issue-number>-plan.md`. That path is a
  symlink (wired in `wire-worktree`) into the shared, persistent project `plans/`
  directory, so any plan `/kit:design` wrote — in this or a prior session — is
  visible here.
- **A specified issue.** An issue that carries a written brief is the same
  artifact published somewhere more durable, and a project whose tickets are
  written that way should not be made to produce a second copy. It qualifies on
  one test, judged from the body and comments `fetch-issue` already fetched — no
  extra lookups:

  > It states **testable acceptance criteria** and **what's out of scope**.

  A body that describes a problem without saying when it's solved is a ticket,
  not a brief, and falls through to `/kit:design` below.

  **The project's AFK-ready triage label (`ready-for-agent` in the canonical
  vocabulary) is not part of that test.** A label is a claim about the body; the
  body is the evidence, and the evidence is readable either way. Gating on the
  label as well sends an issue that answers everything a plan would back to
  `/kit:design` because nobody applied a sticker — routine on projects where the
  same person files and implements and never labels their own tickets. Read the
  label where it exists, for the freshness dating below and as corroboration.
  Never withhold qualification for its absence, and don't ask the user to go add
  it.

  This is not in tension with `/kit:tend-prs`, which *does* require the label
  when it sweeps for startable tickets. There the label is a query filter over
  work nobody asked for, and picking up an unlabelled issue would mean starting
  something unbidden. Here a human has already named the issue, so the only
  question left is whether its body settles the approach.

Judge the issue on that contract alone. Length, formatting, and section headings
are not the test; a short brief that answers both points qualifies and a long
narrative that answers neither does not.

**If both exist, read both — the plan file wins on conflict.** It is the later,
more specific artifact. Say so rather than silently picking, because a
contradiction between them usually means the issue was re-scoped after the plan
was written, and that's worth a sentence to the user.

**If either artifact is present**, read it and treat its *reasoning* as settled — the why, the chosen approach, the rejected alternatives, and the acceptance criteria. Do NOT relitigate those decisions or re-derive the approach from scratch; that's what the `/kit:design` session already did.
- After reading it, **ask the user before doing any verification work**: "Is this still fresh — written recently, and nothing relevant has changed in the codebase since?"
  - **Yes (fresh):** Skip the anchor-verification pass. Present a brief summary and ask whether to proceed or adjust — no file lookups needed.
  - **No (may be stale, or unsure):** Run the anchor-verification pass below.
- **Ask it for an issue too, and expect "no" more often.** An issue is *designed* to sit in the queue until someone picks it up — days or weeks — so an issue brief is stale by default in a way a plan written an hour ago is not. Date it from the most recent evidence the brief was still being maintained: the AFK-ready label's application where there is one, otherwise the last substantive edit or comment. Not from when the issue was opened — that is the one date almost guaranteed to be wrong.
- **Anchor-verification pass** (cheap and bounded — a handful of lookups, not a full re-exploration):
  1. Spot-check every concrete anchor it names — do those files/symbols still exist and look as described? (Targeted grep, or a symbol-lookup MCP tool such as Serena's `find_symbol` if one is available — grep alone is sufficient.)
  2. `git log` the touched area since it was written — did anything land that invalidates an assumption?
- **Decide:** anchors verify + no contradicting drift → present it as-is and proceed. An anchor is missing/moved, or drift contradicts an assumption → the intent still holds, but re-derive the map *in just the affected area* and flag the divergence to the user before proceeding.
- Note: the more concrete file/line detail an artifact asserts, the *more* verification it needs, not less — there's more surface to have gone stale. A well-written brief names interfaces and behavior rather than paths precisely so there is less to rot; verify what it *does* name.
- Present a summary and the verification result, then ask the user whether to proceed or adjust.

**If neither is present**, do NOT improvise an ad-hoc plan and do NOT start implementing. The ticket has no settled approach yet, so the required next step is to **invoke the `/kit:design` skill** before proceeding.
- Run `/kit:design` with this issue number. The issue states the problem; `/kit:design`'s job is the *how* — placement, approaches, the grilling pass, and the durable handoff artifact.
- Write the plan to `$MAIN/plans/<issue-number>-plan.md` (the repository-root `plans/` store, symlinked into this worktree — see `wire-worktree`).
- Once it's written, re-enter this step at the **"If either artifact is present"** branch above: present the summary, run the anchor-verification pass, and ask the user whether to proceed or adjust before any implementation.
- **An unspecified issue is not a failure of the issue.** Falling through to here is the normal path for a ticket filed as a lean problem statement, which is how `/kit:architect` writes them. Don't report it as something missing or push the user to go back and rewrite the ticket.

**Step 11 · `placement-check` — Placement check (only if the work adds or moves a class):**

**If `/kit:ship-ticket` invoked this command, skip this step entirely.** Its `tdd`
phase owns the placement check and runs it there, next to the code being
written — where a different answer can still change the file cheaply. Running it
here too just asks the same question twice, several gates apart.

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

**If `/kit:ship-ticket` invoked this command**, it is already at its `tdd` phase —
say nothing about handoff and return. Do not suggest re-invoking it; that
restarts the orchestrator from `clean-check`.

**If the user ran this command directly**, tell them what they have and what
comes next:

> "Worktree `<worktree>` is ready on `<branch-name>`, plan accepted. Run
> `/kit:ship-ticket <issue-number>` to implement it — TDD, simplify pass, PR,
> automated review, merge, cleanup. It will detect this worktree and resume from
> the implementation phase rather than recreating anything.
>
> Or implement here yourself, and reach for `/kit:commit` and
> `/kit:new-pull-request` when you're ready."

Either way, do not begin implementing. `placement-check` above is the last step
this command owns.


