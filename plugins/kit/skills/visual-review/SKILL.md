---
name: visual-review
description: "Assess someone's pull request for a reviewer in one Gist-first page: the gist, the issue's acceptance criteria rated met/partial/missed, graded evidence, code-shape flags, whether automated reviews were addressed, whether the description matches the code, reversibility, and whether to walk it. Use when asked to review, assess, or triage a PR, or to decide whether a PR needs a hands-on walkthrough or can be trusted to its automation."
metadata:
  credits:
    - skill: pr
      author: Matt Pocock
      url: "https://github.com/mattpocock/skills/blob/013860c/engineering/pr/SKILL.md"
---

The reviewer's side of `visual-pr`. Builds the same read from the diff and the linked issue, whatever the description says — and tells the reviewer where to drill in and where to trust the automation.

**You are not a fixer, and you do not post.** Every finding is a pointer for the reviewer to look at. Never edit the PR's code, push to its branch, comment, or submit a review.

## Gather

Read everything before writing anything:

- **The PR** — `gh pr view <n> --json number,title,author,headRefOid,additions,deletions,body,files,closingIssuesReferences`,
  then `gh pr diff <n>`.
- **The linked issue's body**, not just its number. Its acceptance criteria are the lens. If
  it has no AC section, use its stated requirements and say the criteria are implicit.
- **CI at HEAD** — `gh pr checks <n>`.
- **Automated reviews** — the reviews, their commit, and every review thread with its
  resolved state and replies, in one GraphQL call:

  ```bash
  gh api graphql -f query='query{repository(owner:"<owner>",name:"<repo>"){pullRequest(number:<n>){
    reviews(first:30){nodes{author{login} state submittedAt commit{oid}}}
    reviewThreads(first:100){nodes{isResolved isOutdated path line
      comments(first:10){nodes{author{login} body createdAt}}}}}}}'
  ```

  A Claude review is the PR comment carrying `<!-- claude-pr-review -->`. Compare each
  review's commit with HEAD: a review of an earlier commit did not see the fixes after it.
- **Screenshots** — download each `user-attachments` image from the description into the
  scratchpad and look at it:
  `curl -sL -H "Authorization: token $(gh auth token)" -o shot1.jpg <url>`.
  Judge it against the criteria, not against the caption.

## Verify cheaply

Where a claim can be checked by reading code — a comment saying input is sanitized, a guard
said to cover a path — read it and say it holds or doesn't. Where it can only be settled by
running the app, tag it `[suspected-from-code]` and give it a Walkthrough step. Cite
`file:line` at the PR's HEAD, not at `main`.

## Template

```markdown
# Visual Review — #<pr> <title>

**Verdict:** <Trust automation | Walk it (targeted) | Walk it (full) | Hold> — <one line: why>
<author> · <+adds/−dels> · HEAD `<sha>` · CI <green | red | pending> · Fixes #<issue>

## Gist

<2–4 sentences>

<optional: one diff-sketch, call tree, or file tree>

## Acceptance Criteria

**<n> met · <n> partial · <n> missed** — criteria are <explicit | implicit>; <clear | ambiguous: which, and how the PR read it>

| # | Criterion | Status | Proven by |
|---|---|---|---|
| 1 | <criterion, in the issue's words> | met / partial / missed | <screenshot n, spec name, or "nothing"> |

## Evidence — <Strong | Adequate | Weak | None>

**Screenshots: <grade>** · <n> images
<one line per gap>

**Specs: <grade>** · <passing at HEAD | failing | not run>
<one line per criterion with no load-bearing spec>

## Code Shape

| Kind | New or changed | Closest analogue | Consistent? |
|---|---|---|---|
| <model / service / action / controller / serializer / job> | `<Class#method>` | `<existing class>` | yes / no: <how> |

**Flags to look at** — pointers for the reviewer, not fixes:
- **<count name>** `<file:line>` — <what was seen> · <the caller it costs, or the change it makes harder>

## Automated Reviews

| Reviewer | Reviewed | Findings | Addressed | At HEAD? |
|---|---|---|---|---|
| Claude | `<sha>` or none | <n> | <n resolved / n replied / n open> | yes / no |
| Copilot | `<sha>` or none | <n> | … | yes / no |

<one line per finding not addressed, or addressed only by a reply>

## Description Check

Does the PR description match what the code does?

- **Unstated:** <behaviour the code changes that the description does not mention>
- **Unsupported:** <a description claim the code or evidence does not back>
- **Out of scope:** <changes the issue did not ask for>
- **Checked, holds:** <a claim you verified>

## Reversibility

**Undo:** <easy | costly | one-way> — <confirmed | generated | disputed: author said X>
<what undoing it takes in production>

**Blast Radius:** <one word> — <who is hit if it is wrong, and how it shows up>

## Walkthrough

1. <step> → settles <finding>
```

## Sections

Skip preambles and keep prose brief. Write for a reviewer who reads only the verdict and the
Gist. Use the domain's nouns from `docs/Dictionary-of-Nomenclature.md`. Drop a bullet or row
that has nothing in it rather than writing "none" in each.

### Verdict

- **Trust automation** — evidence Strong, every automated finding addressed at HEAD, nothing
  unstated, undo easy.
- **Walk it (targeted)** — a specific finding needs eyes; the Walkthrough lists only those.
- **Walk it (full)** — evidence Weak or None on a UX change, or the criteria are ambiguous
  enough that the reviewer must judge the whole flow.
- **Hold** — CI red, a criterion missed, an automated finding open, or undo one-way with
  nothing in the description about it.

### Gist

Name the core data structure, payload, or migration — or say there is none. If the change is
mostly UX, name the objective. A visual only when it makes the point faster than prose: a
`diff` sketch of the methods that changed, or a call tree.

### Evidence

Grade screenshots and specs separately; the heading takes the lower.

- **Strong** — every criterion proven: a screenshot for each visible one, a load-bearing spec
  for each behavioural one, passing at HEAD.
- **Adequate** — the key criteria proven; each gap named and low-risk.
- **Weak** — a key criterion unproven, screenshots that don't match the criteria, or specs
  that only pass: nothing would fail if the criterion broke.
- **None** — no screenshots on a UX change, or no specs on a behaviour change.

A non-visual change grades Screenshots `n/a`, not None. A spec is load-bearing when it would
fail if the criterion broke — see `kit:rails-load-bearing-specs` when the call is close.

### Code Shape

List each new or changed model, service, action, controller, serializer, job, and helper.
Name its closest existing analogue, and say whether it is built the same way. Placement is
the author's call; inconsistency with the analogue is what to report.

Then flag what will be hard to maintain. These are `kit:rails-codebase-design`'s §2 counts
and §1's declarative-name property, under its names:

- **First-parameter receiver** — a class method whose first argument is the record it
  operates on: an instance method that never moved onto the instance. Worst with one caller.
- **Hidden instance** — a class method that builds an instance and calls it once, while that
  instance exposes something its callers now cannot reach.
- **Undeclarative name** — a long name narrating what the method does instead of what it
  returns: `build_preview_string`, not `preview`.
- **Fixed-key hash** — a method returning a hash whose keys are literal: a domain object that
  was never named, and cannot be tested as a type.
- **Keyed lookup handed out raw** — a caller digging into a returned hash by a key it builds or
  knows.
- **Duplicated answer** — a rule the app already defines, restated.
- **Unheld namespace** — behaviour filed under the data it reads rather than the caller it
  serves.

Not a flag: a serializer's or presenter's output hash (it is the format), framework
conventions, a length limit on its own. Every flag must name the caller it costs or the
change it makes harder; one that can name neither is dropped.

### Automated Reviews

For each finding: fixed in code (name the commit), answered by a reply only, or open. "Fixed"
from the author is a claim — confirm it in the diff. Say whether each reviewer saw HEAD.

### Description Check

Compare the description and code comments with what the diff does. The unstated change is
the most valuable finding here: a behaviour change the description never mentions is the one
a reviewer cannot know to look for.

### Reversibility

`easy` (a revert, a flag, or a small follow-up fixes it), `costly` (undoable but hard to
deploy and harder to back out — an index on a large table), or `one-way` (dropped or
rewritten data, a backfill, a notification already sent, an external system told). With a
migration, one-way unless its `down` restores the data. Mark it `confirmed` when the
description said the same, `generated` when it said nothing, `disputed` when you disagree.

### Walkthrough

Only steps that settle a finding above, each naming it — a `[suspected-from-code]` finding
always gets one. "None — automation covers it." when the verdict is Trust automation. To walk
the steps, the user runs `/start-review` or `/walkthrough`; name them and pause, never invoke.

## Output

Read the `## Visual PR and review output` section of `CLAUDE.md` at the repo root:

```markdown
## Visual PR and review output
- Format: html (the .md is always kept)
- Location: tmp/reviews/pr-<n>/
```

- **Format** — `markdown` or `html`. Always write `visual-review.md`. With `html`, also
  render a preview beside it and open it:
  `python3 -I <this skill's base directory>/scripts/render_html.py <location>/visual-review.md`.
- **Location** — the directory, with `<n>` the PR number. It must resolve inside a project
  directory, never the monorepo root.

If the section is missing, ask once for both values, offering `markdown` and
`tmp/reviews/pr-<n>/` as defaults. Then offer to add the section to `CLAUDE.md`,
and write it only on a yes. If they decline, use the answers for this run only.

Then relay the verdict line and the top finding in chat, with the file path. Don't repeat the page.
