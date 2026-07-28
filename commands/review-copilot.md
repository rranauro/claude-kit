---
model: sonnet
---

Review and address automated PR review feedback one by one — **GitHub Copilot** (inline + top-level review) and the **Claude Opus headless review** posted by the `pr-review-on-create.sh` hook. Overlapping findings on the same `(path, line)` are merged into one bucket, so the user is asked once — and agreement across reviewers is called out as a stronger signal.

> Despite the file name, this skill is the single addresser for *all* automated PR review comments. Kept the name for backward compatibility with existing references.

**Step 1 — Find the PR:**
- Run `gh pr view --json number,url,title` to get the current branch's PR.
- If no PR exists, tell the user and stop.

**Step 2 — Fetch all automated review feedback:**

Pull from these sources in parallel:

- **Copilot inline:** `gh api repos/{owner}/{repo}/pulls/{number}/comments --jq '.[] | select(.user.login | test("copilot|github-actions"; "i")) | {source: "copilot-inline", id, path, line, body, diff_hunk}'`
- **Copilot top-level review:** `gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq '.[] | select(.user.login | test("copilot|github-actions"; "i")) | {source: "copilot-review", id, state, body}'`
- **Claude headless review:** `gh api repos/{owner}/{repo}/issues/{number}/comments --jq '.[] | select(.body | startswith("<!-- claude-pr-review -->")) | {source: "claude-review", id, body}'` — note this hits the **issues** endpoint (PR-level comments), not pulls/comments. The Claude reviewer posts under the human user's gh account, so the `<!-- claude-pr-review -->` HTML marker (set by `~/.claude/hooks/pr-review-on-create.sh`) is the authoritative way to find it. It may be absent if the headless run hasn't posted yet or found nothing; treat it like any empty source.

> **Match logins case-insensitively** (the `"i"` flag is required). Copilot's *inline* comments are authored by login `Copilot` (capital C), while its top-level review bot is `copilot-pull-request-reviewer[bot]` (lowercase). Without `"i"` the inline pass silently returns nothing — the most important findings get missed.

If all fetched sources are empty, tell the user "No automated review comments found" and stop.

**Step 2.5 — Parse the marker-comment reviews and dedup overlaps:**

The Claude review arrives as a single marker comment (`<!-- claude-pr-review -->`) in Markdown format. Parse it:
- Bullets under `### Inline findings` start with `` **`<path>:<line>`** — <finding> `` — parse `(path, line, finding-text)` from each.
- Bullets under `### General notes` (or anything outside `### Inline findings`) are top-level observations; treat them as one collective general item (`claude-review-general`) with the section text as the body.

If the `<!-- claude-pr-review -->` comment is not present (the headless run hasn't posted yet or found nothing), there are no marker-comment findings to merge beyond Copilot's; skip straight to the bucket build with only Copilot inline entries.

Build a dedup map keyed by `(path, line)`:
- For each Copilot inline comment, add to bucket `(path, line)` with `source: "copilot-inline"`.
- For each parsed Claude inline finding, add to the same bucket if it exists, otherwise create one with `source: "claude-review"`.
- A bucket with two or more entries = overlap; present it once with every source's wording shown together (the user assesses one merged item, not two or three). Agreement across reviewers is a stronger signal — flag it in Step 3.

Items that do NOT have a `(path, line)` — Copilot top-level reviews and the general-notes items — are processed separately after the inline-bucket pass. Do not try to substring-match them against inline findings; the false-positive risk is too high.

Final ordering for Step 3:
1. Inline buckets, sorted by file then line.
2. Copilot top-level review bodies.
3. General notes (Claude).

**Step 3 — Process each item:**
For each item, in order:

1. **Show the item** — display the file path and line number (for inline buckets) or the section type (for top-level Copilot review / general notes), then quote the feedback. **For overlap buckets, label every source** — e.g. `[copilot-inline + claude-review]` — and show each reviewer's wording so the user sees what each said.
2. **Read the relevant code** — read the file around the mentioned lines to understand context.
3. **Assess the item** — categorize it:
   - 🔴 **Must fix** — security issue, bug, or correctness problem
   - 🟡 **Should fix** — code quality, maintainability, or clarity improvement
   - 🟢 **Optional** — style preference, nitpick, or suggestion that doesn't improve the code meaningfully
   - ⚪ **Ignore** — false positive, already handled, or not applicable to our codebase
4. **Classify scope** — is the fix **minor**? A fix is minor when ALL of the following are true:
   - Localized: touches ≤ 3 lines and ≤ 1 file
   - Safe: no behavior change visible to callers (renaming a local variable, adding a missing `nil` guard, correcting a typo, adjusting a log message, removing an unused variable, etc.)
   - Low-risk: no new dependencies, no architectural change, no change to a public API or DB schema
   - If the fix requires understanding cross-file context or redesigning a method signature, it is **not** minor.
5. **Explain your reasoning** — briefly describe the problem, the category, and the scope. When reviewers agree on the same `(path, line)`, that's a stronger signal — lean toward acting on overlap buckets.
6. **Act automatically — no user confirmation needed:**
   - 🔴 **Must fix** → **always apply the fix**, regardless of scope.
   - 🟡 **Should fix** → **always apply the fix**, regardless of scope.
   - 🟢 **Optional** AND **minor** → apply the fix.
   - 🟢 **Optional** AND **non-minor** → skip (noted in summary).
   - ⚪ **Ignore** → skip (noted in summary).

**Step 4 — (removed — no per-item user gate):**
All items are processed without stopping for approval. The summary in Step 5 is the user's review point.

**Step 5 — After all items are processed:**
- Summarize for the user: how many auto-fixed, how many skipped (non-minor or ignored), and why. Break the count out by source (copilot-inline / copilot-review / claude-review / overlap) so the user can see whether one reviewer is consistently noisy or consistently right.
- If any fixes were made, the commit message must capture the per-item evaluation so it's durable in git history (not just the conversation). Format:

  ```
  Address PR review feedback

  - <path>:<line> [Must fix] (copilot+claude) <one-line reasoning> — auto-fixed
  - <path>:<line> [Should fix] (copilot) <one-line reasoning> — auto-fixed
  - <path>:<line> [Optional / minor] (claude) <one-line reasoning> — auto-fixed
  - <path>:<line> [Optional / non-minor] (claude) <one-line reasoning> — skipped
  - <path>:<line> [Ignore] (claude) <one-line reasoning> — false positive, no change
  - top-level (copilot-review) [Optional / non-minor] <one-line reasoning> — skipped
  ```

  Use the four categories from Step 3.3, add the minor/non-minor scope label, and tag each line with the source(s). **Include skipped items too** — the durable record of "we considered this and decided not to act" is the point. If Step 6 delegates to `/commit`, pass this body as the intended message rather than letting `/commit` draft its own.
- If no fixes were made (all comments skipped/ignored), do NOT create a commit. The evaluation summary lives only in the conversation; there is nothing to push.

**Step 6 — Quality gates (if any fixes were made):**
- Run the /commit skill

**Step 7 — Push:**
- Push the branch to origin.

**Step 8 — Enable auto-merge:**
- First-pass automated reviews have now been addressed (per `feedback_no_auto_merge_until_reviews_addressed.md`), so it's safe to mark the PR for auto-merge on CI green.
- Run `gh pr merge <PR#> --auto --squash` (use the PR number resolved in Step 1).
- Run even if no fixes were made — the act of triaging all items counts as "addressed."
- If the command errors because auto-merge is already enabled or the PR is already merged, that's fine — report and continue.
- Tell the user: "Auto-merge enabled — PR will merge when required CI checks pass."

**Arguments:** $ARGUMENTS
If the user passes a PR number (e.g., `/review-copilot 228`), use that instead of the current branch's PR.
