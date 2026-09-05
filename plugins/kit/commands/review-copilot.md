---
model: sonnet
---

Review and address automated PR review feedback one finding at a time — **GitHub Copilot** (inline + top-level review), and the **Claude review** posted by the `pr-review-on-create` hook or `/kit:start-review`, wherever one of those ran. Each finding is verified against the actual code before it is acted on, and overlapping findings on the same `(path, line)` are merged into one bucket — agreement across reviewers is called out as a stronger signal.

> **There is no per-item user prompt.** Verification is empirical, not interactive: findings are checked against the code and applied or skipped automatically (Step 3), and the user's review point is the summary in Step 5 plus the commit body that records every decision.

> Despite the file name, this skill is the single addresser for *all* automated PR review comments. Kept the name for backward compatibility with existing references.

**Step 1 — Find the PR:**
- Run `gh pr view --json number,url,title,labels` to get the current branch's PR. The labels are read again at Step 8 to decide the merge — fetched once here rather than paid for twice.
- If no PR exists, tell the user and stop.

**Step 2 — Fetch all automated review feedback:**

Pull from these sources in parallel:

- **Copilot inline:** `gh api repos/{owner}/{repo}/pulls/{number}/comments --jq '.[] | select(.user.login | test("copilot|github-actions"; "i")) | {source: "copilot-inline", id, path, line, body, diff_hunk}'`
- **Copilot top-level review:** `gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq '.[] | select(.user.login | test("copilot|github-actions"; "i")) | {source: "copilot-review", id, state, body}'`
- **Claude review:** `gh api repos/{owner}/{repo}/issues/{number}/comments --jq '.[] | select(.body | startswith("<!-- claude-pr-review -->")) | {source: "claude-review", id, body}'` — note this hits the **issues** endpoint (PR-level comments), not pulls/comments. The reviewer posts under the human user's gh account, so the `<!-- claude-pr-review -->` HTML marker (set by `scripts/pr-review.sh`) is the authoritative way to find it. It's posted automatically by the `pr-review-on-create` hook wherever a project has registered it, or by a manual `/kit:start-review`; absent either, treat that like any empty source.

> **Match logins case-insensitively** (the `"i"` flag is required). Copilot's *inline* comments are authored by login `Copilot` (capital C), while its top-level review bot is `copilot-pull-request-reviewer[bot]` (lowercase). Without `"i"` the inline pass silently returns nothing — the most important findings get missed.

If all fetched sources are empty, tell the user "No automated review comments found" and stop.

**Step 2.4 · `round-already-closed` — Check whether this round is already closed:**

Look for a `<!-- kit-review-closed -->` comment on the PR in what Step 2 already
fetched — it hits the issues endpoint, so the marker comment is in that result.
No extra call.

- **Unattended, a present marker means stop.** Report that the round is closed
  and quote the summary it carries. Copilot reviews on create, so the automatic
  path has one round to close; running again re-derives an answer already on the
  PR and stacks a second summary saying so.
- **Attended, a present marker does not stop you.** A person typing this command
  is the deliberate re-review. Say the round was already closed and when, then
  carry on — and at Step 7.5 **update that comment in place** rather than posting
  a second one.

**Step 2.5 — Parse the marker-comment reviews and dedup overlaps:**

The Claude review arrives as a single marker comment (`<!-- claude-pr-review -->`) in Markdown format. Parse it:
- Bullets under `### Inline findings` start with `` **`<path>:<line>`** — <finding> `` — parse `(path, line, finding-text)` from each.
- Bullets under `### General notes` (or anything outside `### Inline findings`) are top-level observations; treat them as one collective general item (`claude-review-general`) with the section text as the body.

If the `<!-- claude-pr-review -->` comment is not present (the hook isn't registered for this project, nobody ran `/kit:start-review`, or it found nothing), there are no marker-comment findings to merge beyond Copilot's; skip straight to the bucket build with only Copilot inline entries.

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

**Step 5 · `summarize` — After all items are processed:**
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

  Use the four categories from Step 3.3, add the minor/non-minor scope label, and tag each line with the source(s). **Include skipped items too** — the durable record of "we considered this and decided not to act" is the point. If Step 6 delegates to `/kit:commit`, pass this body as the intended message rather than letting `/kit:commit` draft its own.
- If no fixes were made (all comments skipped/ignored), do NOT create a commit — there is nothing to push. The summary still becomes the record at Step 7.5: a round that skipped everything is closed, and a PR cannot otherwise show the difference between that and a round nobody ran.
- **Report the summary back to your caller in a form it can act on**, naming explicitly whether any **non-minor** item was skipped. The merge decision branches on exactly that: a skipped non-minor item is the difference between enabling auto-merge and escalating to the user. Do not bury it in prose counts.

**Step 6 — Quality gates (if any fixes were made):**
- Run the /kit:commit skill
- **Gate what you changed, not the suite.** The push is what CI reads, and CI
  runs everything again — so a broad local run buys a second copy of an answer
  already on its way, at this pass's expense rather than the runner's. These
  gates exist to catch the fix that is obviously wrong before it costs a full CI
  round and another firing: the specs covering the files you touched, and lint on
  those files.
- **A gate that cannot run is a gate that failed.** A missing runtime, a broken
  shim, an interpreter that isn't on `PATH` — none of these mean the fixes are
  fine, they mean nothing checked them. Treat it exactly as a red gate: stop,
  and report what could not run and why. Unattended this is the difference
  between a review fix that was verified and one that merely compiles in
  someone's head, and the failure reads as an environment footnote rather than a
  refusal unless this step insists otherwise.

**Step 7 — Push:**
- **Push the branch to origin, whatever Step 6 concluded.** What an escalation
  withholds is auto-merge, not the commit. Step 8 is where a failed or unrunnable
  gate stops the round; the push is not that lever, and using it as one loses the
  work instead of holding it.
- **A commit this pass does not push may not survive the pass.** On a laptop the
  worktree persists and "committed locally" means recoverable. On a CI runner the
  checkout is destroyed with the job, so the same words describe a deleted commit
  — and the escalation comment then sends a person to a ref that exists nowhere,
  with no diff to read, having reported the fix as applied. A pass cannot tell
  which of the two it is running on, so it must assume the one where withholding
  is destructive.
- **Say in the escalation that the gates did not run**, and pushing stops being
  indistinguishable from a verified round: the comment is what tells them apart,
  and `kit-escalated` keeps the CI gate off the PR either way. It also gets the
  fix in front of the gate that *can* run it — CI has the toolchain a runner's
  permission grant or a laptop's missing runtime denied this pass.
- If the push itself is rejected, that is its own escalation reason below, and
  the diff belongs in the comment instead — it is the only copy left.

**Step 7.5 · `close-the-round` — Record that the round is closed:**

Run this **whatever the outcome, and in both modes** — especially when nothing
was fixed. A round where every finding was verified and skipped is as closed as
one that pushed a fix, and the PR has no way to show the difference between that
and a round nobody ran.

This used to live only on the unattended path, which meant a round handled in
session left no evidence and the next CI firing paid for a model to rediscover
it. Whoever closes the round writes the record; the caller does not decide.

It sits after the push because the record has to carry the whole outcome: a gate
that could not run and a rejected push are both escalation reasons, and neither is
known at Step 5.

Two writes, together:

```
gh pr comment <N> --body "<!-- kit-review-closed -->
<the Step 5 summary>"
gh pr edit <N> --add-label kit-review-closed
```

**The comment is authoritative and the label is for the gate.** The comment
carries the summary and any escalation reason, which is the durable record. The
label carries only the fact that a round closed, so a CI gate can decide from
`gh pr list --json labels` — data it already has — instead of paying a call per
PR to look for a comment. On divergence the comment wins, and a missing label
with a present comment fails toward waking a model, which is the safe direction.

Create the label once per repo with `gh label create kit-review-closed`, or from
the UI. A repo that has not is not broken: the comment still closes the round, and
the gate over-approximates by waking a model that finds nothing to do.

**Re-running attended, edit the existing comment rather than posting a second.**
Step 2.4 already told you it was there. Find it by its marker and edit by id:

```
gh api --method PATCH repos/{owner}/{repo}/issues/comments/<id> -f body=@<file>
```

Two summaries on one PR read as two rounds, and the second is the one anybody
trusts — which is the duplicate this step exists to prevent.

**Escalations go in this same comment**, never a later one. A pass that posts the
marker and then dies leaves a PR reading as a clean closed round, which is this
record inverted:

```
gh pr comment <N> --body "<!-- kit-review-closed -->
<!-- kit-escalated: skipped a non-minor optional item -->
<the Step 5 summary>"
```

The escalation reason is the one thing only the comment holds —
`kit-review-closed` is on the PR either way, because a gate should skip an
escalated PR for the same reason it skips a closed round: what it needs is a
person, not another model pass.

`## Unattended` below owns what the escalation *conditions* are, and the merge
decision that branches on them. This step owns only the record.

**Step 8 · `enable-auto-merge` — Enable auto-merge (gated):**

The first-pass automated review round is now closed, which is the precondition
for auto-merge — triaging every item counts as "addressed" even when no fixes were
made. Auto-merge stays off until this point precisely because CI often goes green
before the reviewers post.

**If this skill was invoked by `/kit:ship-ticket`, stop here.** That command
opens its PR with auto-merge deliberately off and leaves it to the CI gate;
enabling it here would merge a PR whose review round nobody has closed.

"Stop here" ends *this* skill, not the caller's run. Return the
Step 5 summary and let the caller continue — a pass that treats this as the end of
its own work leaves the round closed with auto-merge never enabled, which is the
one state nothing downstream is watching for.

**Run unattended, decide the merge yourself** — see `## Unattended` below, which
owns that decision. Do not also ask. The record is already written: Step 7.5 does
that in both modes.

Otherwise, ask the user before enabling:

> "Review findings addressed and pushed. Enable auto-merge (squash) for PR #<N>? GitHub will merge once checks pass."

- On approval, run `gh pr merge <PR#> --auto --squash` (use the PR number resolved in Step 1).
- If the command errors because auto-merge is already enabled or the PR is already merged, that's fine — report and continue.
- If it errors because auto-merge is disabled in repo settings, say so and let the user merge from the GitHub UI; do not fall back to a local merge.
- **If the user declines, record it as `kit-hold` on the PR**, then stop:

  ```
  gh pr edit <PR#> --add-label kit-hold
  ```

  Declining is a decision, and until it is written down it survives only as long
  as this session. A CI gate enables auto-merge on any closed-round, green PR it
  has not been told to leave alone, so an unrecorded decline is reversed by the next
  firing and GitHub merges the PR you just held back. This is the same pattern
  `/kit:new-pull-request` uses — a human answered a prompt, and the command
  records the answer where the next reader will find it.

  Say that you wrote it, and say how to undo it: `gh pr edit <PR#> --remove-label
  kit-hold` hands control back, after which the PR is judged on its evidence
  again — round closed, green and unheld, which the gate will act on.

  **Only this branch writes the label, and only attended.** Unattended has no
  prompt to decline, so it has no decision to transcribe; it escalates instead,
  and `## Unattended` owns what that means. Nothing here ever *removes*
  `kit-hold` — clearing it is the human's statement, the same as on an issue.
- On success, tell the user: "Auto-merge enabled — PR will merge when required CI checks pass."

**Arguments:** $ARGUMENTS
If the user passes a PR number (e.g., `/kit:review-copilot 228`), use that instead of the current branch's PR.

`unattended` alongside the number (`/kit:review-copilot 228 unattended`) says
nobody is watching. It is passed by a caller and **never inferred** — a session
that looks quiet is not a session with no one in it.

---

## Unattended

A PR needs two things before anyone looks at it again: a record of what happened,
and a decision about merging. **Step 7.5 already wrote the record**, in both modes
— that is a fact about the round, and which caller ran it changes nothing. What is
left here is the decision, which attended belongs to the person and unattended
belongs to you. You are the only one holding the per-item reasoning, and
re-deriving it costs another pass.

**A held PR still gets its round closed — a hold only ever withholds the merge.** If the
labels fetched at Step 1 carry `kit-hold`, run every step above as normal —
Step 7.5 records the round the same as any other PR's — but skip the merge:
report the round as closed and held, and stop. A hold names a PR a person is
already in charge of merging; this pass does not call `gh pr merge` over that
decision, and it does not remove the label either — clearing `kit-hold` is the
human's statement, the same as everywhere else in this file.

**Otherwise, decide the merge.** On a clean triage, `gh pr merge <N> --auto --squash`.
With a single review round there is nothing further to wait for, and leaving it
off means the PR sits green until someone notices. Enabling it is idempotent, and
the merge stays GitHub's to perform once checks pass.

**Escalate instead — leave auto-merge off — when any of these hold:**

- You skipped a **non-minor** item: a finding real enough to record and too large
  to apply alone.
- The gates failed, could not be run at all, or the push was rejected. A gate that
  never ran is not a gate that passed, and unattended that is the likelier of the
  two. The fixes are pushed regardless — see Step 7 — so what this withholds is
  the merge, and the comment is what marks the round as unverified.
- `gh pr checks <N>` shows a failing required check. **Repairing it is not your
  job** — a red check is not a review finding, and repairing one belongs in a
  session with a person nearby. Escalate and say so.

An escalation is carried by the comment Step 7.5 writes, in the same body as the
marker. Hand it the reason before it writes; do not post a later comment saying
the round escalated after all.
