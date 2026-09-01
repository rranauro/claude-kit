Clean up a feature-branch worktree after its PR has been merged on GitHub.

**Arguments:** $ARGUMENTS
Optional: a branch name, worktree path, or PR number. If omitted, infer from the current branch.

This command targets the worktree case from `kit:start-ticket`. If the branch was bundled onto an existing worktree instead of getting its own, only Step 6's branch deletion applies — no worktree to remove.

**Step 1 — Resolve the target:**
- If `$ARGUMENTS` is a PR number: `gh pr view <num> --json headRefName,state,mergedAt` and take `headRefName` as the branch.
- If `$ARGUMENTS` is a branch name: use it directly.
- If `$ARGUMENTS` is a path: derive the branch from `git worktree list`.
- If empty: use the current branch (`git rev-parse --abbrev-ref HEAD`). If that's `main`, ask the user which worktree to clean up.

Resolve `<worktree>` — the branch's path — from `git worktree list --porcelain`, and run the `kit:worktree-conventions` skill to find out whether the project owns worktree teardown. If git lists no worktree for the branch, surface what you found and ask the user before proceeding.

**If the project has a remove command, that command is Step 5.** A project recipe routinely does more than `git worktree remove` — unlinking a dev proxy, dropping a registered subdomain, deleting generated config — and those are exactly the parts you cannot reconstruct afterward. Steps 2-4 still apply as written; Step 5 becomes running it.

**Step 2 — Verify the PR is merged:**
- `gh pr view <branch-name> --json state,mergedAt,url,number`
- If state is not `MERGED`, STOP and warn the user. Do not clean up unmerged work.
- If no PR exists for the branch, STOP and ask the user before proceeding — the work may not be intended for cleanup.

**Step 3 — Verify the worktree has no uncommitted work:**
- `git -C <worktree> status --porcelain`
- **Known-safe leftovers (do NOT prompt about these — silently allow + use `--force` in Step 5):**
  - Any untracked path that is a **symlink `kit:start-ticket` `wire-worktree` created** back into the main checkout. Those are setup artifacts, not work. Confirm with `test -L <path>` rather than matching names — the set is project-specific.
  - In practice that means the secrets, permissions, and dependency links `wire-worktree` wires up — e.g. `?? .claude/settings.local.json`, `?? config/credentials.yml.enc` (Rails), and any vendored `node_modules` symlinks the project needs.
  - Any **deleted tracked path shadowed by one of those symlinks** — an ancestor directory of the entry is itself such a link. A link created *over* a tracked directory hides the files git expects inside it, so git reports them deleted for the worktree's whole life; `wire-worktree` linking Rails' `storage/` produces a permanent ` D storage/.keep`. Same setup artifact as the bullet above, spelled as a deletion rather than an untracked entry, and the one this check would otherwise read as work. Confirm by walking the entry's ancestors up to the worktree root and testing each with `test -L`, never by matching `storage/` or any other name. Restoring the file is not the fix — the checkout writes *through* the link into the main checkout, and the deletion comes straight back.
- If the porcelain output contains **only** entries from the known-safe set above, treat it as clean and proceed silently. Mark `--force` as required for Step 5 and continue.
- If the porcelain output contains **anything else** (modified tracked files, untracked files outside the known-safe set), STOP and report what's outstanding. Do NOT pass `--force`; ask the user how to handle the leftovers.

**Step 4 — Confirm the branch isn't active elsewhere:**
- Ask the user explicitly: "Is `<branch-name>` checked out in another terminal, IDE, or worktree?"
- If yes, STOP. Leave the worktree and branch alone — the user has live work there.

**Step 5 — Remove the worktree (run from the main checkout):**
- Before removing, stop any **per-directory daemon** bound to this worktree's path. Tools that run a persistent server per working directory orphan their process when the directory is deleted underneath them — harmless individually, but they accumulate across tickets and idle-burn CPU/memory. Don't prompt; these are routine and no-ops when nothing is running. On Rails that's RuboCop's server mode: `cd <worktree> && rubocop --stop-server; cd -`. Substitute your stack's equivalent (language servers, watchers, test daemons).
- `git worktree remove <worktree>` — or `git worktree remove --force <worktree>` if Step 3 flagged `--force` required. If the project owns teardown, run **its** remove command instead and do not follow it with a raw `git worktree remove`; it already ran one.
- If the user is currently `cd`'d into the worktree being removed, ask them to switch to the main checkout first; otherwise the remove will fail.
- **Always sweep the path afterward.** `git worktree remove` deregisters git's bookkeeping but routinely leaves behind runtime files written while the app was booted in the worktree — caches, logs, uploads — some with read-only permissions their writer set. (On Rails the usual culprit is `tmp/cache/bootsnap/`.) After the `worktree remove` succeeds, unconditionally run `chmod -R u+rwX <worktree-path> 2>/dev/null; rm -rf <worktree-path>` so VS Code, Finder, and `ls` don't see an orphan directory. Do not prompt — this is a no-op if the path is already gone.
  - `u+rwX` rather than `u+w`: a cache directory the writer left non-traversable cannot be descended into to delete what is under it, so `rm -rf` fails with `Permission denied` on the directory itself and the sweep leaves the husk it was meant to remove. `X` adds execute to directories only, never to files.

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
