---
name: shape-review
description: Judge the object shape a pull request introduces — its new classes, signatures and call sites, scored on kit:rails-codebase-design with placement included — as one Markdown comment a person can post as written. Use when a PR's author was an unattended agent, when asked to review a diff's shape or placement, or when another skill needs a shape review of a PR.
---

# Shape Review

The diff is the first place the shape counts can fire. A design pass has a prose
proposal and one call site per method, so `kit:rails-codebase-design` §2 has
nothing to count; a diff has committed signatures and every call that reaches
them. And what a diff *introduces* is a short, complete list in a way a whole
area is not.

**Placement is in scope here.** `kit:visual-review` leaves placement to the
author, because the author is a colleague whose call it respects. The author
this skill reviews is usually an unattended agent whose design nobody argued
with, so where the behavior lives is exactly what needs judging.

**You produce one comment and change nothing.** No label, no commit, no push, no
post, no file in the repository. Posting is the reader's decision — they post it
as written, edit it first, or drop it.

**Argument:** a pull request number.

## 1 — Gather

```bash
gh pr view <n> --json number,title,headRefOid,files,closingIssuesReferences
gh pr diff <n>
```

Read a changed file at the PR's HEAD when a hunk alone cannot say what a method
reads of `self` or who calls it — `gh api repos/{owner}/{repo}/contents/<path>?ref=<sha>`.
Grep the PR's tree for callers when a finding needs the census. Cite `file:line`
at HEAD.

## 2 — Inventory what the diff introduces

Three lists, built from added and changed lines only. Untouched code is out of
view — context lines in a hunk, and every file the diff does not touch, are
there to read, never to judge.

- **New classes, modules and namespaces** — including a concern, and a class
  reopened to gain a public method.
- **New or changed public method signatures** — written the way
  `kit:behavior-placement` "What to hand back" writes them: the `initialize`
  line verbatim, and each public method as `#name(args) -> ReturnType`. A
  signature you cannot write is itself the finding that check describes.
- **New call sites** — every added line that calls something in the first two
  lists, or that the diff changed the signature of.

The inventory is complete when every added public method in a Ruby or Stimulus
file appears in it once. It goes into the comment whatever the findings, so a
reader can tell a clean diff from one that was not looked at.

## 3 — Judge

For every inventory entry:

- **Count it** against `kit:rails-codebase-design` §2, by name. Use the counts
  exactly as written there — the borrowed receiver is counted by enumerating
  what each new method reads of `self`, the keyed lookup by what the new call
  site does with the hash.
- **Place it**, for each new class or moved behavior, with `kit:behavior-placement`
  Checks 1–3: whose behavior it is, whether the app already derives the answer,
  and who produces and consumes it.
- **Gate it** on `kit:rails-codebase-design` §3. A finding on the not-a-finding
  list is dropped. A finding that cannot name the caller it costs, or the change
  it makes harder, is dropped too — that test is the bar a finding clears, not a
  field to fill.

## 4 — Write each finding from the call site

A reader judges a finding from the call site without opening the class, so every
finding leads with it: the line as the diff writes it, then the line as it would
read after the fix. Below that, the panels of `kit:rails-codebase-design` §1.5 —
**caller**, **model**, **class** — each present only when the fix touches it.
The model panel is where a narrowing lands, and leaving it out is how a fix
preserves the record argument it was meant to remove.

## 5 — The comment

The marker is the first line, so the comment is recognisable whoever's account
posts it:

````markdown
<!-- kit-shape-review -->
## Shape review — #<pr> at `<short sha>`

**<n> findings** · <n> classes · <n> signatures · <n> call sites inventoried

### 1. <count name> — `<Class#method>`

**Call site now** (`<file:line>`)
```ruby
<the line as the diff writes it>
```

**After**
```ruby
# caller
<the call site>

# model — <what moved here, or omit the panel>
<the reader it gained>

# class — <omit the panel when the fix needs no class>
<initialize line and #method -> Type lines>
```

**Costs:** <the caller it costs, or the change it makes harder>
**Placement:** <Check that decided it: where it lives, where it belongs> — omit when placement is not in question

<details><summary>Inventory</summary>

| Kind | Introduced | Signature |
|---|---|---|
| class / signature / call site | `<name>` (`<file:line>`) | `<initialize(...)` or `#m(...) -> T`> |

</details>
````

Order findings strongest first: a placement finding above a naming one, a count
with several callers above one with one.

**With no findings**, the comment says so in its first line under the heading —
`**No shape findings.**` — and still carries the inventory, open rather than
folded, since it is now the whole content. A diff touching no Ruby or Stimulus
file says that instead of producing an empty table.

## 6 — Deliver

Your final message is the comment, starting at the marker line — no preamble, no
closing remark, no surrounding fence. A caller capturing the output, or a person
piping it to `gh pr comment <n> --body-file -`, gets exactly the body.
