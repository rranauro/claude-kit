Clean up a feature-branch worktree after its PR has been merged on GitHub.

**Arguments:** $ARGUMENTS
Optional: a branch name, worktree path, or PR number. If omitted, infer from the current branch.

This command targets the worktree case from `/start-ticket` (worktree at `.claude/worktrees/<branch-name>/`). If the branch was bundled onto an existing worktree instead of getting its own, only Step 6's branch deletion applies — no worktree to remove.

**Step 1 — Resolve the target:**
- If `$ARGUMENTS` is a PR number: `gh pr view <num> --json headRefName,state,mergedAt` and take `headRefName` as the branch.
- If `$ARGUMENTS` is a branch name: use it directly.
- If `$ARGUMENTS` is a path: derive the branch from `git worktree list`.
- If empty: use the current branch (`git branch --show-current`). If that's `main`, ask the user which worktree to clean up.

Confirm the worktree path is `.claude/worktrees/<branch-name>/` via `git worktree list`. If it isn't listed there, surface what you found and ask the user before proceeding.

**Step 2 — Verify the PR is merged:**
- `gh pr view <branch-name> --json state,mergedAt,url,number`
- If state is not `MERGED`, STOP and warn the user. Do not clean up unmerged work.
- If no PR exists for the branch, STOP and ask the user before proceeding — the work may not be intended for cleanup.

**Step 3 — Verify the worktree has no uncommitted work:**
- `git -C .claude/worktrees/<branch-name> status --porcelain`
- **Known-safe leftovers (do NOT prompt about these — silently allow + use `--force` in Step 5):**
  - `?? lib/mcp/theme-gallery/node_modules` and `?? lib/mcp/unsplash/node_modules` — symlinks `/start-ticket` Step 7 creates back to the main checkout's `node_modules`. They're setup artifacts, not work.
  - `?? .claude/settings.local.json`, `?? config/credentials.yml.enc` — symlinks `/start-ticket` Step 7 creates to inherit the main checkout's permissions and credentials.
- If the porcelain output contains **only** entries from the known-safe set above, treat it as clean and proceed silently. Mark `--force` as required for Step 5 and continue.
- If the porcelain output contains **anything else** (modified tracked files, untracked files outside the known-safe set), STOP and report what's outstanding. Do NOT pass `--force`; ask the user how to handle the leftovers.

**Step 4 — Confirm the branch isn't active elsewhere:**
- Ask the user explicitly: "Is `<branch-name>` checked out in another terminal, IDE, or worktree?"
- If yes, STOP. Leave the worktree and branch alone — the user has live work there.

**Step 5 — Remove the worktree (run from the main checkout):**
- Before removing, stop any RuboCop server daemon bound to this worktree's path: `cd .claude/worktrees/<branch-name> && rubocop --stop-server; cd -`. RuboCop's server mode spawns a persistent background process per directory; if the directory is deleted without stopping it first, the process orphans and keeps running indefinitely (harmless individually, but they accumulate across tickets and idle-burn CPU/memory). Don't prompt — this is a routine cleanup step, and a no-op if no server is running for that path.
- `git worktree remove .claude/worktrees/<branch-name>` — or `git worktree remove --force <path>` if Step 3 flagged `--force` required.
- If the user is currently `cd`'d into the worktree being removed, ask them to switch to the main checkout first; otherwise the remove will fail.
- **Always sweep the path afterward.** `git worktree remove` deregisters git's bookkeeping but routinely leaves behind `tmp/cache/bootsnap/` (read-only perms set by Ruby) and other runtime files if the Rails app was booted in the worktree. After the `worktree remove` succeeds, unconditionally run `chmod -R u+w <worktree-path> 2>/dev/null; rm -rf <worktree-path>` so VS Code, Finder, and `ls` don't see an orphan directory. Do not prompt — this is a known artifact of having booted the Rails app in the worktree, and a no-op if the path is already gone.

**Step 6 — Sync local main and delete the branch:**
- `git fetch origin main && git pull --ff-only origin main` from `main` first, so the local ref reflects the merge.
- `git branch -d <branch-name>` — try the safe delete first.
- If git refuses with "not fully merged" **and Step 2 already confirmed PR state is `MERGED`**, the cause is a squash-merge (the local branch's commits aren't ancestors of `main` because squash collapses them into one new commit). Escalate to `git branch -D <branch-name>` silently — do **not** prompt. The merge has been verified upstream; the local branch is a stale pointer.
- If git refuses for any other reason (Step 2 didn't run, or PR state was something other than `MERGED`), STOP and surface the error. `-D` requires explicit user approval in that case.

**Step 7 — Prune stale refs:**
- `git worktree prune`
- `git remote prune origin` — cleans up remote-tracking refs for branches GitHub already deleted on merge.

**Step 8 — Report:**
- Summarize for the user: worktree path removed, branch deleted, PR URL and number.
