---
model: sonnet
description: Collate the automated reviews on a pull request and address each finding against the code, recording every decision. Use when `kit:ticket-loop` or `/kit:start-review` hands off a PR whose reviews have landed, or when a CI gate calls it unattended.
license: MIT — Copyright (c) 2026 Ron Ranauro, https://github.com/rranauro/claude-kit
---

Review and address automated PR review feedback one finding at a time — **GitHub Copilot** (inline + top-level review), the **Claude review** posted by the `pr-review-on-create` hook or `/kit:start-review`, wherever one of those ran, and a **shape review** — `kit:shape-review`'s comment, posted by whoever ran it. Each finding is verified against the actual code before it is acted on, and overlapping findings on the same `(path, line)` are merged into one bucket — agreement across reviewers is called out as a stronger signal.

> **There is no per-item user prompt.** Verification is empirical, not interactive: findings are checked against the code and acted on or not automatically (Step 3), and the user's review point is the summary in Step 5 plus the commit body that records every decision.

> Despite the file name, this skill is the single addresser for *all* PR review comments it collates. Kept the name for backward compatibility with existing references.

**Step 1 — Find the PR:**
- Run `gh pr view --json number,url,title,labels,baseRefName` to get the current branch's PR. The labels are read again at Step 8 to decide the merge, and the base is what Step 3 asks *Belongs* against — both fetched once here rather than paid for again.
- If no PR exists, tell the user and stop.

**Step 2 — Fetch all automated review feedback:**

Pull from these sources in parallel:

- **Copilot inline:** `gh api repos/{owner}/{repo}/pulls/{number}/comments --jq '.[] | select(.user.login | test("copilot|github-actions"; "i")) | {source: "copilot-inline", id, path, line, body, diff_hunk}'`
- **Copilot top-level review:** `gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq '.[] | select(.user.login | test("copilot|github-actions"; "i")) | {source: "copilot-review", id, state, body}'`
- **Claude review:** `gh api repos/{owner}/{repo}/issues/{number}/comments --jq '.[] | select(.body | startswith("<!-- claude-pr-review -->")) | {source: "claude-review", id, body}'` — note this hits the **issues** endpoint (PR-level comments), not pulls/comments. The reviewer posts under the human user's gh account, so the `<!-- claude-pr-review -->` HTML marker (set by `pr-review.sh`) is the authoritative way to find it. It's posted automatically by the `pr-review-on-create` hook wherever a project has registered it, or by a manual `/kit:start-review`; absent either, treat that like any empty source.
- **Shape review:** `gh api --paginate repos/{owner}/{repo}/issues/{number}/comments --jq '.[] | select(.body | startswith("<!-- kit-shape-review -->")) | {source: "shape-review", id, updated_at, body}' | jq -s 'max_by(.updated_at) // empty'` — the same endpoint as the Claude review. `--paginate` applies `--jq` page by page, so the latest is picked by the second `jq` over every page's matches; picking it inside `--jq` sees only one page of thirty. **Find it by the marker, never by author**: the common case is a reviewer who edited what `kit:shape-review` printed and posted it from their own account. Address the body as GitHub returns it, edits included, and never re-run the shape pass to regenerate it. **Where several marked comments exist, the most recently updated is the review** — a reviewer who reposts rather than edits means the new one, and addressing both applies the wording they replaced.

> **Match logins case-insensitively** (the `"i"` flag is required). Copilot's *inline* comments are authored by login `Copilot` (capital C), while its top-level review bot is `copilot-pull-request-reviewer[bot]` (lowercase). Without `"i"` the inline pass silently returns nothing — the most important findings get missed.

**Read `## Review sources` from the project's rules** (`kit:project-rules`) —
`copilot`, `claude-review`; absent, both. It changes no fetch and no finding — only how
Step 5 names an empty source: **not run** if undeclared, **missing** if declared.

If all fetched sources are empty, tell the user "No automated review comments found", skip to Step 5 to name each source not run or missing, and close the round at Step 7.5. Stopping here leaves a round nobody can tell from one that never ran.

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

The shape review is one marker comment too, in the format `kit:shape-review` §5 writes. Parse it:
- Each `` ### <n>. <count name> — `<Class#method>` `` section is one finding. Key it on the `file:line` its **Call site now** line names.
- The **After** panels are the fix the reviewer proposes, and **Costs** / **Placement** are its reasoning — carry all three as the finding text.
- A heading ending `— contested` carries several **After — <move>** blocks and marks none preferred, each followed by its **Score:** line. Carry them all, scores included; Step 3 does not pick one.
- The `<details><summary>Inventory</summary>` block is not a finding, and neither is the `**Not judged:**` line. A comment reading `**No shape findings.**` is an empty source.

If the `<!-- claude-pr-review -->` comment is not present (the hook isn't registered for this project, nobody ran `/kit:start-review`, or it found nothing), there are no Claude findings to merge; build the buckets from the sources that did land.

Build a dedup map keyed by `(path, line)`:
- For each Copilot inline comment, add to bucket `(path, line)` with `source: "copilot-inline"`.
- For each parsed Claude inline finding, add to the same bucket if it exists, otherwise create one with `source: "claude-review"`.
- For each parsed shape finding, the same, with `source: "shape-review"`.
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

   **A shape finding is never 🟢 Optional.** It is 🔴 or 🟡, so it is applied, unless verifying it against the code shows its premise false, which makes it ⚪: the call site it names is gone, or the fix already landed. It skips the two questions below: it has already been gated once by the pass that printed it, then chosen by the person who posted it. The fix is commits on this branch through Steps 6 and 7 — never a new ticket or PR. **A contested shape finding is the exception**: the axis could not choose between its Afters, so applying one would make the choice the PR was held for. Mark it ⚪ with that as the reason and leave it to the person at the hold — `kit:reshape` is where it is decided.
4. **Ask who it affects** — the *Affected* test in `CONTEXT.md`. **Nobody**
   drops it.
5. **Ask whether it belongs to this PR** — the *Belongs* test in `CONTEXT.md`.
   Before the first item, `git fetch origin <baseRefName>` — the caller's
   checkout may hold only the PR head, or a stale base — then read the PR's diff
   once (`git diff origin/<baseRefName>...HEAD`); a finding inside a hunk
   usually settles from it. Where it does not — the finding sits outside every hunk, or turns on
   reachability or a widened exposure — read the base branch's version of the
   code it names, `${CLAUDE_PLUGIN_ROOT}/scripts/base-show.sh origin/<baseRefName> <path>`
   (`kit:project-rules` says why not `git show`). Never run anything to
   decide it. **A base that cannot be fetched or compared is a gate that could
   not run** (Step 6): say so in the summary rather than guessing which findings
   belong.
6. **Explain your reasoning** — briefly: the problem, the category, who it
   affects, and whether it belongs. When reviewers agree on the same
   `(path, line)`, that's a stronger signal — lean toward acting on overlap
   buckets.
7. **Act automatically — no user confirmation needed.** Every finding ends in
   one outcome, and its summary line names it:
   - ⚪ **Ignore** → no change, `false positive`.
   - **Affects nobody** → no change, `dropped — affects nobody`.
   - **Belongs** → apply the fix, whatever its size or category: `fixed`.
     **Unless the code cannot settle it** — it needs an in-app look, a wording
     or product call, or an owner's decision. Then no fix is applied, since
     applying one is making that call, and the outcome is `left for the person`:
     Step 7.4 writes it into the PR body, held or not, and on an unheld PR
     Step 7.5 pins it. **It needs a question the owner decides, whose answer
     changes something.** A finding you cannot put that way — whichever answer
     the owner gave, nothing would be done differently — is `dropped — affects
     nobody`, not left: there is nothing to look at, so it goes on neither the
     PR nor the store.
   - **Outside the diff** → no fix: `outside the diff — named here`. The round
     summary names it in full, and Step 7.5 pins the PR. It is real, and it is
     not this ticket's — absorbing it widens the PR past what was asked, and
     recording it where the person doesn't look loses it. **One exception:** a
     minor fix may still be applied, and the outcome is then `fixed`. A fix is
     minor when it touches ≤ 3 lines in 1 file, changes nothing a caller can
     see, and adds no dependency, public API or schema change.

   A contested shape finding stays ⚪ as above: the posted shape review already
   carries it to the person, and `kit:reshape` decides it.

   **A PR is held** when Step 1's labels carry `kit-hold`. Step 7.4 reads it.

**Step 4 — (removed — no per-item user gate):**
All items are processed without stopping for approval. The summary in Step 5 is the user's review point.

**Step 5 · `summarize` — After all items are processed:**
- Summarize for the user: how many ended in each outcome Step 3 names, and why. Break the count out by source (copilot-inline / copilot-review / claude-review / shape-review / overlap) so the user can see whether one reviewer is consistently noisy or consistently right.
- Name each automated source that posted nothing as **not run** or **missing**, by the declaration Step 2 read. This summary is what Step 7.5 records, so the distinction reaches the PR.
- If any fixes were made, the commit message must capture the per-item evaluation so it's durable in git history (not just the conversation). Format:

  ```
  Address PR review feedback

  - <path>:<line> [Must fix] (copilot+claude) <one-line reasoning> — fixed
  - <path>:<line> [Optional] (claude) <one-line reasoning; who it affects> — fixed
  - <path>:<line> [Optional] (claude) <one-line reasoning> — dropped — affects nobody
  - <path>:<line> [Ignore] (claude) <one-line reasoning> — false positive, no change
  - <path>:<line> [Should fix] (shape) <one-line reasoning> — fixed
  - <path>:<line> [Should fix] (copilot) <one-line reasoning> — left for the person — in the PR's Instructions
  - <path>:<line> [Must fix] (claude) <who it affects, and what they get; the same on the base branch> — outside the diff — named here
  - top-level (copilot-review) [Should fix] <one-line reasoning> — outside the diff — named here
  ```

  Use the categories and outcomes from Step 3, and tag each line with the source(s). **Include every finding, whatever its outcome** — the durable record of "we considered this and decided not to act" is the point. Write a finding outside the diff whole: where, who it affects, what they get. If Step 6 delegates to `/kit:commit`, pass this body as the intended message rather than letting `/kit:commit` draft its own.
- **The summary carries these per-item lines too, commit or not.** It is what Step 7.5 posts, and the round summary on the PR is where a finding outside the diff is named — a commit body alone leaves it in history nobody holding the PR reads.
- If no fixes were made, do NOT create a commit — there is nothing to push. The summary still becomes the record at Step 7.5: a round that fixed nothing is closed, and a PR cannot otherwise show the difference between that and a round nobody ran.
- **Report the summary back to your caller in a form it can act on**, naming explicitly whether any finding ended `outside the diff — named here`, and whether any was left for the person on an unheld PR. Either outcome pins the PR — a finding outside the diff that the minor-fix exception resolved ends `fixed` and pins nothing, per Step 7.5, and the caller cannot recover it from prose counts. It does not decide the merge: a pinned PR still merges.

**Step 6 — Quality gates (if any fixes were made):**
- Invoke `kit:commit` through the Skill tool
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
  and `kit-hold` keeps the CI gate off the PR either way. It also gets the
  fix in front of the gate that *can* run it — CI has the toolchain a runner's
  permission grant or a laptop's missing runtime denied this pass.
- If the push itself is rejected, that is its own escalation reason below, and
  the diff belongs in the comment instead — it is the only copy left.

**Step 7.4 · `leave-for-the-person` — Put what is left where the person looks:**

Skip it when Step 3 left nothing for the person. Otherwise write each finding
as one numbered item — what to look at, then what would settle it — into a
file, and run:

```
${CLAUDE_PLUGIN_ROOT}/scripts/pr-body-left.sh <N> <items-file>
```

The person holding the PR reads its body, and the Instructions section is where
they look for what to check; a summary comment sits where they do not. Do not edit the body any other way — the script is what keeps the
rest of it as the author wrote it.

**The body is these findings' record.** On a held PR they get no
`kit-pinned`: it names a PR that merged
carrying an open question, and a held PR's question is answered before it
merges. An unheld PR can merge before anyone reads its body, so Step 7.5 pins
it.

**A write that fails loses them unless it is said.** Report what the script
printed, and in Step 7.5's summary list each finding in full under `left for
the person — not written to the PR body`, so the round summary carries them
instead.

**Step 7.5 · `close-the-round` — Record that the round is closed:**

Run this **whatever the outcome, and in both modes** — especially when nothing
was fixed. A round where every finding was verified and none fixed is as closed as
one that pushed a fix, and the PR has no way to show the difference between that
and a round nobody ran.

This used to live only on the unattended path, which meant a round handled in
session left no evidence and the next CI firing paid for a model to rediscover
it. Whoever closes the round writes the record; the caller does not decide.

It sits after the push because the record has to carry the whole outcome: a gate
that could not run and a rejected push are both escalation reasons, and neither is
known at Step 5.

Two writes, and the second is conditional on the first:

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

**The comment failing means the round did not close.** Do not label, do not
escalate, and report the round as unrecorded, naming what the comment write
said. The label is what makes every gate skip this PR, so applying it over a
summary that never landed is the one state nothing downstream can recover from.
`docs/labels.md` is the rule and the argument for it.

Read the comment call's own result rather than asking GitHub again. `gh pr
comment` prints the new comment's URL on success and exits non-zero otherwise,
so the round has its confirmation without a second call.

A repo with no such label is not broken: the comment still closes the round, and
the gate over-approximates by waking a model that finds nothing to do. **Say the
mark did not apply, and that the round itself is recorded** — the summary is on
the PR, so nobody needs to re-run this round to recover what it decided, and
re-running would stack a second summary. `label-write-failed` below is the rule.

**Re-running attended, edit the existing comment rather than posting a second.**
Step 2.4 already told you it was there. Find it by its marker and edit by id:

```
gh api --method PATCH repos/{owner}/{repo}/issues/comments/<id> -f body=@<file>
```

Two summaries on one PR read as two rounds, and the second is the one anybody
trusts — which is the duplicate this step exists to prevent.

**An escalation adds one more write, and states its reason in this same
summary**, never a later comment. A pass that posts the marker and then dies
leaves a PR reading as a clean closed round, which is this record inverted:

```
gh pr edit <N> --add-label kit-hold          # escalating: this one goes first
gh pr edit <N> --add-label kit-review-closed
```

Both marks belong on an escalated PR — the round did close, and a gate should
skip it for the same reason it skips any closed one: what it needs is a person,
not another model pass.

**On an escalation the hold is written first, and `kit-review-closed` only if it
landed.** The two marks pull in opposite directions: `kit-hold` stops the merge
and `kit-review-closed` is what permits it. A gate arms auto-merge on a
closed-round, green, unheld PR — so a hold that failed while the closed mark
succeeded is not a partial escalation, it is the escalation reversed, and the
next firing merges the thing this pass stopped.

If the hold cannot be applied, **leave the round unclosed**: report the
escalation, say `kit-review-closed` was deliberately withheld, and name
`gh label create kit-hold` as what fixes it. An unclosed round costs a later
pass that re-derives this one. That is the price of the only ordering where
neither failure merges the PR.

**`kit-hold` is what survives this pass.** Withholding auto-merge is the absence
of an action, not a record: a CI gate arms auto-merge on any closed-round, green
PR it has not been told to leave alone, so an escalation kept only as a comment
is reversed by the next firing and GitHub merges the thing this pass escalated.
The label is the one mark on a PR that outlives the session that wrote it, and it
is the same mark a person's own veto uses — one mechanism, whoever set it.

The reason stays prose in the summary and the label carries none, which is the
split `kit-review-closed` already draws. Encoding it into the label name would
give the gate a vocabulary to parse and the repo a label per reason.

**A later run of this pass finds its own label**, and that is the mechanism
working rather than the pass tripping over itself. `## Unattended`'s hold check
sees `kit-hold`, closes the round again, reports it closed and held, and does not
merge. This pass never removes the label — not even the one it set.

**A finding that ended `outside the diff — named here` is not an escalation,
and takes a different write** — and so does one left for the person on an
unheld PR. One the minor-fix exception resolved ended `fixed`, leaves no
question open, and takes neither. Each is a
question to answer later, not a merge to stop: holding the PR over it strands
finished work behind a question nobody has scheduled. The summary comment above
already names it, so mark the PR and let the merge proceed:

```
gh pr edit <N> --add-label kit-pinned   # only if the comment posted
```

The summary comment is the record, on the PR the person holding it reads. The
label is the filter `gh pr list --label kit-pinned` reads (`CONTEXT.md`
**kit-pinned**), and never a vocabulary.

**A finding left for the person on an unheld PR goes to the store only when no
summary on the PR names it.** That is the comment above failing to post, with no
earlier round's summary naming the finding either: a re-run whose edit failed
still has the old summary and its pin. Then the store is the one place the
question is waited on. Record one each
through `kit:observations`, `--waiting owner` and `--pr <N>`, with its `action`
stating the question the owner decides, and name it as recorded in the report to
your caller. Where the comment posted, it, the body and `kit-pinned` are the
record, and a copy in the store could only be deleted at triage. A body write
that failed does not count: the summary lists those findings in full. A refused
store write is reported and changes nothing else here. **Nothing else this round
handled goes to the store.**

`## Unattended` below owns what the escalation *conditions* are, and the merge
decision that branches on them. This step owns only the record.

**Step 7.6 · `label-write-failed` — Say when a mark did not land:**

**Every `--add-label` in this command** — the two above, `kit-pinned` below, and
the declined-merge hold in Step 8 — can be refused, because the label does not
exist in this repo and the grant denies `gh label`. Report which label, on which
PR, and what the unrecorded decision was, then carry on with the rest of the
step.

Leave the label uncreated and let the repo owner run `gh label create <name>`.
An unattended pass may not mint vocabulary the whole repo then inherits, which
is why the grant denies it; `docs/labels.md` carries that argument.

Every label in this command, the Step 1 read included, is in the project's
spelling (`kit:project-rules` *Labels*). **Where the project has no `kit-hold`**, an escalation
follows the failed-hold branch above — the summary states it,
`kit-review-closed` is withheld, nothing is merged — and the report says the
project has no hold label rather than that a write failed.

**Step 8 · `enable-auto-merge` — Enable auto-merge (gated):**

The first-pass automated review round is now closed, which is the precondition
for auto-merge — triaging every item counts as "addressed" even when no fixes were
made. Auto-merge stays off until this point precisely because CI often goes green
before the reviewers post.

**If this skill was invoked by `/kit:ship-ticket`, stop here.** That pass has
work left on the PR after this round closes — marking a draft ready — and it
arms auto-merge itself once the run that transition triggers has registered.
Arming it here would let the PR merge before either happened — while it is still
a draft, or against the checks the draft earned.

"Stop here" ends *this* skill, not the caller's run. Return the
Step 5 summary and let the caller continue — a pass that treats this as the end of
its own work leaves the round closed with auto-merge never enabled, which is the
one state nothing downstream is watching for.

**First, whether anything here may arm at all — in both modes.** Resolve it,
and `<method>`, from the rules Step 2 read, as `kit:ticket-loop` `hand-off`
step 5 does. Where that leaves the PR for a person, do not arm and do not ask:
report it, with step 5's reason, and stop. Write no `kit-hold` — that is the
project's standing rule, not a decision about this PR, and a CI gate re-running
this step reads the same rule.

**Run unattended, decide the merge yourself** — see `## Unattended` below, which
owns that decision. Do not also ask. The record is already written: Step 7.5 does
that in both modes.

Otherwise, ask the user before enabling:

> "Review findings addressed and pushed. Enable auto-merge (<method>) for PR #<N>? GitHub will merge once checks pass."

- On approval, run `gh pr merge <PR#> --auto --<method>` (use the PR number resolved in Step 1).
- If the command errors because auto-merge is already enabled or the PR is already merged, that's fine — report and continue.
- If it errors because auto-merge is not allowed for the repository, that is step 5's left-for-a-person outcome, not a failure: say so and let the user merge from the GitHub UI; do not fall back to a local merge.
- **If the user declines, record it as `kit-hold` on the PR**, then stop:

  ```
  gh pr edit <PR#> --add-label kit-hold
  ```

  Declining is a decision, and until it is written down it survives only as long
  as this session. A CI gate enables auto-merge on any closed-round, green PR it
  has not been told to leave alone, so an unrecorded decline is reversed by the
  next firing and GitHub merges the PR you just held back. This is the same pattern
  `/kit:new-pull-request` uses — a human answered a prompt, and the command
  records the answer where the next reader will find it.

  **A refused write is the decline being lost, so say it loudly.** If the repo
  has no `kit-hold` label the edit fails and the paragraph above describes
  exactly what happens next: the gate finds a closed-round, green, unlabelled PR
  and merges it. Tell the user the decline was *not* recorded, that the PR will
  merge on the next firing, and that `gh label create kit-hold` followed by this
  same edit is what holds it. Step 7.6 is the rule; this is the branch where
  ignoring it costs a merge nobody authorised. Then stop — the confirmation
  below describes a hold that is not in place.

  **On a successful edit**, say that you wrote it, and say how to undo it: `gh pr edit <PR#> --remove-label
  kit-hold` hands control back, after which the PR is judged on its evidence
  again — round closed, green and unheld, which the gate will act on.

  **This is not the only branch that writes the label.** Step 7.5 writes it too,
  in either mode, whenever the round escalates — a declined merge and an
  escalation are the same statement, that a person is in charge of this PR, so
  they leave the same mark. Nothing anywhere in this file ever *removes*
  `kit-hold` — clearing it is the human's statement, the same as on an issue, and
  that rule now guards a label this pass may have set itself.
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

**A held PR still gets its round closed — a hold only ever withholds the merge.**
If the labels fetched at Step 1 carry `kit-hold`, run every step above as normal —
Step 7.5 records the round the same as any other PR's — but skip the merge:
report the round as closed and held, and stop. A hold names a PR a person is
already in charge of merging; this pass does not call `gh pr merge` over that
decision, and it does not remove the label either — clearing `kit-hold` is the
human's statement, the same as everywhere else in this file.

**Otherwise, decide the merge.** On a triage that escalated nothing — including
one that pinned the PR — `gh pr merge <N> --auto --<method>`, with
the method Step 8 resolved, unless Step 8 found arming off. With a
single review round there is nothing further to wait for, and leaving it off
means the PR sits green until someone notices. Enabling it is idempotent, and
the merge stays GitHub's to perform once checks pass.

**A pinned PR is not withheld from the merge.** Step 7.5 owns that write. The
reason it is not an escalation is that nothing is unverified: the gates ran, the
round is closed, and what is left is a question whose answer can arrive later.
The two conditions below are the
opposite case — each of them means this pass could not establish that the PR is
sound, and merging on an unestablished claim is what the hold prevents.

**Escalate instead — leave auto-merge off — when any of these hold:**

- The gates failed, could not be run at all, or the push was rejected. A gate that
  never ran is not a gate that passed, and unattended that is the likelier of the
  two. The fixes are pushed regardless — see Step 7 — so what this withholds is
  the merge, and the comment is what marks the round as unverified.
- `gh pr checks <N>` shows a failing required check. **Repairing it is not your
  job** — a red check is not a review finding, and repairing one belongs in a
  session with a person nearby. Escalate and say so.

**A finding is never one of them, and never stops the round to ask** — what it
leaves open is the body's, the pin's and the store's to carry.

An escalation is carried by the `kit-hold` label Step 7.5 applies, with the reason
in the same comment body as the marker. Hand it the reason before it writes; do
not post a later comment saying the round escalated after all.
