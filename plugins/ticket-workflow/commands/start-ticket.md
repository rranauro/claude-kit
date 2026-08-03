---
model: sonnet
---

Start work on a GitHub issue by reading it, creating a worktree off `origin/main`, and planning the implementation.

**Arguments:** $ARGUMENTS
The argument should be a GitHub issue number (e.g., `/start-ticket 42`) or a GitHub issue URL.

Each step below carries a stable id in backticks (`safety-check`, `wire-worktree`,
…). Those ids are the handle other commands reference — `/ship-ticket` and
`/cleanup-worktree` both point at steps here. Renumber freely; **never rename an
id** without updating the references, and grep for one before you delete its step.

**Step 1 · `parse-issue` — Parse the issue reference:**
- Extract the issue number from `$ARGUMENTS`
- If no argument is provided, ask the user for the issue number

**Step 2 · `safety-check` — Safety check (run in parallel, from the main checkout):**
- `git status` — ensure the working tree is clean (no uncommitted changes)
- `git rev-parse --abbrev-ref HEAD` — note the current branch (`git branch --show-current` needs git ≥ 2.22 and fails on older installs)
- `ls .claude/worktrees/ 2>/dev/null | grep "^<issue-number>-"` — check for an existing worktree with the same ticket-number prefix

If there are uncommitted changes, STOP and warn the user. Suggest they commit or stash first.

**If an existing worktree is found** (e.g., `.claude/worktrees/42-add-user-avatar`), present it to the user and ask:
> "A worktree for this ticket already exists: `42-add-user-avatar`. Resume it, or replace it with a fresh one?"

**Invariant: one worktree per issue.** Never create a second, suffix-differentiated sibling for the same issue number (e.g. `935-...-scope` alongside `935-...-fields`). Two live worktrees for one issue is a trap — the dev server can be booted in the stale one, hiding the real changes and reading as "my changes aren't showing." Enforce exactly one of:
- **Resume (default):** Skip `fetch-issue` through `wire-worktree`. Set `<branch-name>` to the existing directory name, then jump to `worktree-paths` — use the existing worktree path for all subsequent reads/edits. Do NOT re-run `wire-worktree` (the symlinks are already there).
- **Replace:** Only if the existing worktree is being abandoned/re-scoped. First confirm it's not checked out elsewhere and has no unmerged work worth keeping (an open PR on its branch means keep it — Resume instead). Then remove the old worktree per `/cleanup-worktree` semantics (`git worktree remove [--force]`, sweep the path) **before** creating the new one. The new branch reuses the `<issue-number>-` prefix and may keep the same name — there is no sibling to collide with once the old one is gone.

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

**Step 6 · `create-worktree` — Create the worktree:**
- `git fetch origin main` — refresh `origin/main` (don't rely on "up to date" from `git status`; that only reflects the last fetch)
- `git worktree add .claude/worktrees/<branch-name> -b <branch-name> origin/main`
- Worktrees live under `.claude/worktrees/<branch-name>/` inside this repo — never as siblings of the main checkout.

**Step 7 · `wire-worktree` — Wire up the worktree:**

A fresh worktree contains only tracked files. Anything gitignored but required
at runtime is missing, and the failures it causes are indirect — blank config,
a boot-time abort, a re-prompt — so wire these up before handing the worktree
over.

Resolve the main checkout once and reuse it, rather than hardcoding a path:

```
MAIN="$(git rev-parse --show-toplevel)"
WT=".claude/worktrees/<branch-name>"
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
  gitignored plan store as the main checkout. This is how `/design`'s
  `plans/<n>-plan.md` reaches `plan-implementation` — without the link a fresh
  worktree has no `plans/` at all and the handoff silently breaks:
  `mkdir -p $MAIN/plans`
  `ln -sfn $MAIN/plans $WT/plans`
  Use `-n` so the link is created *as* `plans` rather than inside an existing
  directory. `plans/` is gitignored, so the symlink won't dirty the worktree.
- **Uploaded-file storage** is often wired by the project's own boot script. If
  yours does that, say so and let it — don't create the link yourself and risk
  conflicting with it.

**Step 8 · `worktree-paths` — Use worktree-prefixed paths from now on:**
- Every subsequent Read/Edit/Write must target `.claude/worktrees/<branch-name>/<file>` (or the absolute equivalent). The tool cwd is still the main checkout.

**Step 9 · `plan-implementation` — Plan the implementation:**
- **First**, check if `.claude/worktrees/<branch-name>/plans/<issue-number>-plan.md` exists. That path is a symlink (wired in `wire-worktree`) into the shared, persistent project `plans/` directory, so any plan `/design` wrote — in this or a prior session — is visible here. This file contains the full architectural context, agreed approach, and key decisions.
  - **If the plan file exists:** Read it and treat its *reasoning* as settled — the why, the chosen approach, the rejected alternatives, and the acceptance criteria. Do NOT relitigate those decisions or re-derive the approach from scratch; that's what the `/design` session already did.
    - After reading the plan, **ask the user before doing any verification work**: "Is this plan fresh (created this session or just recently, and you're confident nothing relevant has changed in the codebase)?"
      - **Yes (plan is fresh):** Skip the anchor-verification pass. Present a brief summary of the plan and ask whether to proceed or adjust — no file lookups needed.
      - **No (plan may be stale, or unsure):** Run the anchor-verification pass below.
    - **Anchor-verification pass** (cheap and bounded — a handful of lookups, not a full re-exploration):
      1. Spot-check every concrete anchor the plan names — do those files/symbols still exist and look as described? (Targeted grep, or a symbol-lookup MCP tool such as Serena's `find_symbol` if one is available — grep alone is sufficient.)
      2. `git log` the touched area since the plan's date — did anything land that invalidates an assumption?
    - **Decide:** anchors verify + no contradicting drift → present the plan as-is and proceed. An anchor is missing/moved, or drift contradicts an assumption → the plan's intent still holds, but re-derive the map *in just the affected area* and flag the divergence to the user before proceeding.
    - Note: the more concrete file/line detail a plan asserts, the *more* verification it needs, not less — there's more surface to have gone stale.
    - Present a summary and the verification result, then ask the user whether to proceed or adjust.
  - **If the plan file does NOT exist:** Do NOT improvise an ad-hoc plan and do NOT start implementing. The ticket has no settled architectural context yet, so the required next step is to **invoke the `/design` skill to create the plan file** before proceeding.
    - Run `/design` with this issue number. The issue states the problem; `/design`'s job is the *how* — placement, approaches, the grilling pass, and the durable handoff artifact.
    - Write the plan to `$MAIN/plans/<issue-number>-plan.md` (the repository-root `plans/` store, symlinked into this worktree — see `wire-worktree`).
    - Once the plan file is written, re-enter this step at the **"If the plan file exists"** branch above: present the summary, run the anchor-verification pass, and ask the user whether to proceed or adjust before any implementation.

**Step 10 · `placement-check` — Placement check (only if the work adds or moves a class):**

If the agreed approach introduces a new model, concern, service, or PORO — or
relocates behavior between them — run the `behavior-placement` skill before
implementation starts. It answers where the behavior belongs (model → value
object → service) and whether the app already derives the answer somewhere.

Run it even when the plan already names a class. A plan file records the
*direction*, and `/architect` deliberately keeps the implementation substrate
out of tickets — so a class name appearing in one is usually shorthand, not a
verified placement decision. This check is where it gets verified.

If the skill is installed per-project rather than globally, read it from the
worktree path (`$WT/.claude/skills/behavior-placement/`), not the main checkout.


