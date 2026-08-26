---
model: opus
---

Walk the user through verifying a change in-app, one step at a time, against a durable checklist that survives detours and session ends.

**Arguments:** `$ARGUMENTS` — a GitHub issue number or URL, optionally followed by free-text notes (e.g. "skip the admin screens"). Required.

---

## What this skill is

A **driver**, not a test plan. It derives an ordered list of things the user can
observe in the running app, persists that list to disk, and then presents
exactly one at a time — stopping after each so the user can report what they saw.

The problem it exists to solve is positional, not verbal. Asking for in-app
instructions already works; what fails is *coming back*. When a step surfaces a
bug and the session turns to fixing it, the walkthrough's position lives only in
the transcript — buried by the detour, erased by a compaction. This skill moves
that position onto disk, so resuming is a file read instead of a scroll-back.

Use it when a branch is ready to exercise: `/kit:ship-ticket` Phase 5 offers it
before the PR is opened. It also stands alone for a re-verification pass.

Do **not** use it as an intake loop for whatever the user happens to notice —
that's `/kit:polish-ticket`. This skill has a finite list and an end.

Constituent skills:
- `/kit:polish-ticket` — `intake` through `file-ticket`, for every detour
- `/kit:ship-ticket` — Phase 5 onward, once the walk finishes

---

## Mandatory constraints

- **Present one step, then stop.** Never render two steps in one turn, and never
  render the list mid-walk. The full list is shown exactly once, at `confirm-list`.
- **Never mark a step from your own expectation.** Only the user's report
  advances the checklist. Presenting a step and marking it passed in the same
  turn makes the artifact record what you predicted rather than what they saw —
  it is the single failure mode that destroys this skill's value.
- **All work happens in the worktree.** Every Read/Edit/Write targets its path,
  resolved from `git worktree list --porcelain` rather than assumed — the layout
  may be the project's, not this suite's. The tool cwd stays at the main checkout.
- **The artifact is the state.** If the walk's position isn't in the file, it
  doesn't exist. Update the file at `record-result`, before doing anything else.
- **Don't boot the app.** The user runs the dev server. Give them the commands
  and what to look for.

---

## The artifact

The `walkthrough` artifact, stored by `kit:ticket-artifacts` — the live copy in
the cache at `plans/<issue>-walkthrough.md`, which the worktree shares with the
main checkout, and a marked comment on the issue that outlives both.

**The cache is the live position; the comment is the record.** Write the file on
every `record-result` — that is what makes the position real. Sync the comment
three times only: at `write-artifact`, at `detour`, and at `finish`. A PATCH per
step puts a network call between every question and the next answer, and nobody
reads the issue mid-walk.

The comment is what stops the walk dying with the worktree.
`/kit:cleanup-worktree` used to take the record of what was actually exercised
with it, at the moment someone was deciding whether to ship anyway.

```markdown
# Walkthrough — #1161 Field values render as plain text
Branch: 1161-plain-text-fields · Derived from AC + diff

- [x] w1 · Open a page with a text field, click into it — editor opens inline
- [ ] w2 · Type `<b>bold</b>`, blur — renders as literal text, not markup  ← CURRENT
- [~] w3 · Skipped — no nested field on this theme
- [!] w4 · Reorder two rows — order persists after reload → #1187
```

Four states:

| Marker | Meaning |
|---|---|
| `[ ]` | Pending — not yet walked, or failed-and-since-fixed and awaiting re-verification |
| `[x]` | Passed — the user reported the expected observation |
| `[~]` | Skipped — the user declined it. Append the reason they gave, if any |
| `[!]` | Failed — append the filed issue number, or the commit if fixed inline |

Exactly one step carries `← CURRENT`. It is the first `[ ]` in file order.

**Do not commit the artifact.** It is per-branch scratch; committing it puts a
verification checklist in the PR diff of every ticket. If the project's `/kit:commit`
gates would sweep it up, say so and leave it out of the staged set explicitly.

---

## Step 1 · `derive-steps` — Turn the ticket into observable steps

Read two sources, in this order:

1. `gh issue view <number>` — the acceptance criteria. These are *outcomes*
   ("field values render as plain text"), not click paths. They tell you what
   must be true, not how to see it.
2. `git -C <worktree> diff origin/main...HEAD` — the change itself. This is what
   turns an outcome into a path: the templates, controllers, and views the diff
   touches are the screens the user has to reach.

An AC bullet with no reachable surface in the diff is a step you cannot derive —
say so rather than inventing a plausible-sounding click path.

**One step = one thing the user observes**, with the navigation to reach it
folded in. Not one step per click, and not one step per AC bullet. "Verify the
field renders as plain text" is one bullet but often several observations across
two screens; split it. Conversely, three clicks that produce one visible result
are one step.

Write each step as: what to do → what should happen. Concrete enough that the
user doesn't have to guess which button, short enough to read in one breath.

If the branch has no worktree yet, or `git log origin/main..HEAD` is empty,
there is nothing to walk — stop and say so.

---

## Step 2 · `confirm-list` — Show the whole list, once

This is the only turn in the entire skill that renders more than one step.

Present the derived list, numbered, and ask the user to merge, split, reorder,
or drop anything before the walk starts. Granularity is their call — they know
the app, and a list they've shaped is one they'll actually follow.

Also state what you could **not** derive: AC bullets with no surface in the diff,
or behavior that needs data you don't know they have. Silent omissions read as
coverage.

**Gate.** Do not write the artifact or present step 1 until they approve the list.

---

## Step 3 · `write-artifact` — Persist it

Store the `walkthrough` artifact in the format above — cache file and comment
both, via `kit:ticket-artifacts`. Give every step a stable `w<n>` id at creation
and never renumber: detour notes, filed issues, and commit messages reference
these ids, and renumbering breaks every reference at once.

Mark `w1` as `← CURRENT`, then go to `present-step`.

**If the artifact already exists, this is a resume — go to `resume` instead.**
Check through the skill, not the filesystem. A walk started in a worktree that
has since been removed, or on another machine, has a comment and no file, and
reading the directory alone would restart it from `w1` and silently discard
everything that was already verified.

---

## Step 4 · `present-step` — One step

Render the current step alone: its id, what to do, what should happen. Nothing
else — no preamble about the ones before it, no preview of what's next.

Then say what the user can report: what they saw, `skip`, or `stop`.

Then **end the turn.** Do not narrate, do not speculate about whether it will
pass, do not begin the next step.

On the first `present-step` of a session only, prefix it with the run command
for the worktree and the URL to open. After that, they're already there.

---

## Step 5 · `record-result` — Advance on the user's report

Update the artifact first, then respond. Three outcomes:

**Matches the expectation** → mark `[x]`, move `← CURRENT` to the next `[ ]`,
return to `present-step`.

**They skip it** → mark `[~]` with their reason if they gave one, move `←
CURRENT`, return to `present-step`. Never argue for the step or ask them to
reconsider; skipping is a first-class outcome, and the artifact records that it
went unverified.

**They report something wrong** → mark `[!]` and go to `detour`.

If what they report doesn't map cleanly onto the current step — a different
screen, an unrelated idea — that is not this step's result. Leave the marker
alone and handle it as an out-of-scope detour.

When no `[ ]` remains, go to `finish`.

---

## Step 6 · `detour` — Hand the problem to triage

A detour is `/kit:polish-ticket`'s loop, entered mid-walk. Do not re-derive it here.

Delegate to `/kit:polish-ticket` `intake` → `triage` → (`fix-inline` | `file-ticket`).
Its rules apply unchanged: locate the cause before triaging, converge in two or
three focused checks, get explicit approval for each fix, one commit per fix.

Two things this skill adds on top:

- **Carry the step id into the record.** The commit subject or filed issue should
  name the observation (`w4: row order lost after reload`), so the artifact's
  `→ #1187` annotation resolves to something months later.
- **Sync the comment before delegating.** A detour is where a walk most often
  ends for good — the fix takes over the session and nobody comes back. Whatever
  was verified up to here should be on the issue before you hand control away.
- **Return by re-arming the step, not by advancing.** When a detour ends in an
  inline fix, flip `[!]` back to `[ ]`, restore `← CURRENT` to it, and go to
  `present-step` — the user re-walks the step to verify the fix. When it ends in
  a filed ticket, leave `[!]` with the issue number and advance to the next `[ ]`.

**Out-of-scope detours.** If the user takes the session somewhere else entirely —
a different area, a new idea, a question about the architecture — follow them.
That is not a failure of the walkthrough. Leave the artifact untouched; the
position is on disk and `resume` will find it whenever they come back.

---

## Step 7 · `resume` — Pick up where the file says

Triggered by re-invoking the command, by the user asking where you were, or by
returning from a long detour.

Read the artifact through `kit:ticket-artifacts` — cache first, then the comment,
which is the copy that survives a removed worktree. Report, in two lines: how
many passed, skipped, and failed, and what's still open. Then go straight to
`present-step` for the `← CURRENT` step. Do not re-derive the list and do not
re-run `confirm-list` — the artifact is authoritative, including over your memory
of the session.

If the branch has gained commits since the walk began, note which — a fix may
have invalidated a step already marked `[x]`, and the user may want it re-armed.
Ask; don't re-arm it on your own judgment.

---

## Step 8 · `finish` — Close the walk

When no `[ ]` remains, summarize the artifact: passed, skipped (with reasons),
and failed (with issue numbers). Skipped and failed steps are the point of this
summary — they are what the branch has *not* been verified against, and the user
is about to decide whether to ship anyway.

Then hand back:

- Invoked from `/kit:ship-ticket` Phase 5 → return there, and let the user decide
  whether the open items block the PR.
- Invoked standalone → ask whether to land, keep fixing, or stop.

Sync the comment one last time and leave both copies in place. It is the record
of what was actually exercised, it's what `resume` reads if the user comes back
with one more thing to check, and on the issue it is readable by whoever reviews
the PR — who otherwise has only the claim that a walk happened.

---

## Failure / interrupt handling

- **Session ends mid-walk.** By design. Re-invoke `/kit:walkthrough <issue>`;
  `resume` reconstructs the position from the file.
- **A step can't be performed** — missing data, a feature behind a flag, a theme
  without the relevant surface. That's a skip with a reason, not a failure. Mark
  `[~]` and move on.
- **The list is wrong once the walk starts** — steps in an impossible order, or a
  screen that doesn't exist. Stop, fix the artifact with the user, keep the ids
  of the steps that survive. Don't push through a list you both know is wrong.
- **The user reports a step passing that you expected to fail.** Mark it `[x]`.
  Their observation is the evidence; yours is a prediction.
- **Fixes accumulate past a handful.** The branch is bigger than a walkthrough —
  say so and offer `/kit:polish-ticket` for the rest, which is built for an open-ended
  intake loop rather than a finite list.
