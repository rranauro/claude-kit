---
name: shape-review
description: Judge the object shape a pull request, or a local diff between a base and a head, introduces — its new classes, signatures and call sites, scored on kit:rails-codebase-design with placement included — as one Markdown comment a person can post as written. Use when a PR's author was an unattended agent, when asked to review a diff's shape or placement, or when another skill needs a shape review of a PR.
license: MIT — Copyright (c) 2026 Ron Ranauro, https://github.com/rranauro/claude-kit
---

# Shape Review

Judge what one diff introduces, on `kit:rails-codebase-design` — a pull
request's, or one between two refs before any PR exists.
**Placement is in scope** — `kit:visual-review` leaves it to the author; this
skill judges it, because the author it reviews is usually an unattended agent
whose design nobody argued with.

**Change nothing.** No label, no commit, no push, no post, no file in the
working tree. The comment is the whole output, and posting it is the reader's
decision.

**Arguments:** a pull request number, or a base and a head — two git refs, for
a diff no PR has been opened on. One token is a PR; two are the refs.

## 1 — Gather

Resolve the base and head to SHAs once, and do every read, diff and grep
locally against them. A PR's SHAs come from GitHub, with its head fetched:

```bash
gh pr view <n> --json headRefOid,baseRefOid
git fetch origin pull/<n>/head        # lands in FETCH_HEAD; creates no branch
```

Two refs are already local, so nothing is asked of GitHub and nothing fetched:

```bash
git rev-parse <base>^{commit} <head>^{commit}
```

Name the base the PR would merge into, at its tip, and the three-dot diff below
takes the same merge base a PR's does — which is what makes the comment the one
that PR would get. From here on nothing differs but §5's heading.

```bash
git diff <base>...<head> -- '*.rb' '*_controller.js'
git show <head>:<path>                # a whole file, when a hunk cannot say what a method reads of self
git diff --name-only <base>...<head>
```

Cite `file:line` at the head SHA.

**The filter is the axis's reach, not the diff's.** From the name list, pick
the files outside it that hold code — a component, a module, a template or
partial; data, config, docs, lockfiles, styles and images carry no object shape.
They are not judged, and §5's `**Not judged:**` line names them, since a review
that skipped them reads as clean otherwise.

## 2 — Inventory what the diff introduces

Three lists, from added and changed lines only. Context lines and untouched files
are there to read, never to judge.

- **New classes, modules and namespaces** — a concern, and a class reopened to
  gain a public method, included.
- **New or changed public method signatures**, in the form
  `kit:behavior-placement` "What to hand back" writes them.
- **New call sites** — every added line calling something in the first two lists.

The inventory is complete when every added public method in the filtered diff
appears in it once. For every existing class the diff gives a new member, also
list the interface it already carried at `<base>` — evidence for the accreted
interface count, read rather than judged. Then find callers for all of them in
one pass — `git grep -n -E '\b(m1|m2|…)\b' <head>` — rather than one grep per
method.

## 3 — Judge

For every inventory entry:

- **Count it** against `kit:rails-codebase-design` §2, by name, exactly as
  written there.
- **Place it**, for each new class or moved behavior, with
  `kit:behavior-placement` Checks 1–3.
- **Gate it** on `kit:rails-codebase-design` §3, closing check included. What
  fails is dropped.

Then, once per object the diff adds to, apply §2's accreted interface to its
members, every added one included. It is one count on the object, so it yields at
most one finding however many members the diff adds there.

Only where that count fires, find the commit behind each existing member it
counted — one blame of the class file, read off each member's definition line,
then one lookup for the subjects. Where blame names a commit that only edited
the line, `git log --format='%h %s' -S '<member>' <base> -- <the class file> |
tail -1` finds the one that added it.

```bash
git blame -s <base> -- <the class file>
git show -s --format='%h %s' <sha> <sha> …
```

Then **contest every finding** but an accreted interface one. Draft the After
the finding calls for, and an After for every other fix that fits it — each
`kit:rails-codebase-design` §2.5 move whose tell the finding shows, and the fix
inside the object where there is one. Gate each After on §3 as the finding was
gated, then score it: the §2 counts it still fires, by name. One After **beats**
another when it clears a count the other still fires.

**A finding is contested when two or more Afters survive and none beats
another.** The axis cannot choose between them; what is left is which callers
each one moves, and that is the person's to weigh. Otherwise the finding carries
the one After that beats the rest, and the others are dropped unwritten — an
alternative the axis beats is a choice already made, and showing it asks a
person to make it again. Most findings have one After. Contested is the
exception, and a caller leaves it for a person to pick, so never call a finding
contested to be thorough.

> contested = two or more Afters survive and none beats another (comparable
> scores); uncontested = one After beats the rest; an obvious better choice is
> never contested.

An accreted interface finding is never contested: it writes no After, so there
is nothing to rank.

## 4 — Write each finding from the call site

A reader judges a finding from the call site without opening the class, so every
finding leads with it: the line as the diff writes it, then as it would read
after the fix, in the **caller**, **model** and **class** panels of
`kit:rails-codebase-design` §1.5 — each panel present only when the fix touches
it.

**A contested finding writes one After per surviving fix**, each headed by the
move it makes — a §2.5 move by name, or `in place` for the fix inside the
object — and marks none preferred — the rank is the person's, and an
order here would make it for them. **Each After carries a score line** under
its panels: the §2 counts it still fires, by name exactly as
`kit:rails-codebase-design` §2 writes them, or that it fires none. The scores
are what show the tie — without them a reader cannot tell a tie from a pick
nobody made, and has to score the Afters again to trust it. An uncontested
finding's one After carries none: the Afters it beat were never written, so a
score would answer a comparison the comment does not show. Since an After that
clears a count the other fires beats it, tied scores name the same counts. A
contested finding's **Costs** gives each After its own line: the call sites outside the diff that move, counted,
since reach is all that is left to separate them.

**An accreted interface finding leaves out the panels.** Its subject is the
object, and the reshape is decided by whoever takes it up, so an **After**
here would be a design nobody asked this pass for. **Call site now** is the first
added member's caller, or its definition when it has none, and any other members
the diff added there are listed in **Costs**. **Costs** names each existing
single-caller member with its one caller — or its definition, when it has none —
and the commit that introduced it — `` `#removed_fields` (`jobs/purge.rb:14`, a1b2c3d Purge removed fields) ``.
It goes in **Costs** because `kit:review-copilot` carries that line and would
drop a new one.

Order findings strongest first: contested findings above the rest, since they
are the choices left to a person; then a placement finding above a naming one, a
count with several callers above one with one.

## 5 — The comment

````markdown
<!-- kit-shape-review -->
## Shape review — #<pr> at `<short sha>`

**<n> findings, <c> contested**

**Not judged:** `<path>`, `<path>` — no axis here for this code; read it yourself.

### 1. <count name> — `<Class#method>` — contested

**Call site now** (`<file:line>`)
```ruby
<the line as the diff writes it>
```

**After — <move>**
```ruby
<the panels, as below>
```
**Score:** fires <count name>, <count name> — or `fires none`

**After — <another move>**
```ruby
<the panels, as below>
```
**Score:** fires <the same count names> — or `fires none`

**Costs:**
- <first move>: <the call sites outside the diff it moves, counted>
- <second move>: <the same>

### 2. <count name> — `<Class#method>`

**Call site now** (`<file:line>`)
```ruby
<the line as the diff writes it>
```

**After**
```ruby
# caller
<the call site>

# model — <what moved here>
<the reader it gained>

# class
<initialize line and #method -> Type lines>
```

**Costs:** <the caller it costs, or the change it makes harder>
**Placement:** <the Check that decided it: where it lives, where it belongs> — only when placement is in question

<details><summary>Inventory</summary>

| Kind | Introduced | Signature |
|---|---|---|
| class / signature / call site | `<name>` (`<file:line>`) | `<initialize(...)` or `#m(...) -> T`> |

</details>
````

**Given two refs, the heading is ``## Shape review — `<short head sha>` ``** —
there is no PR to number, so the head names what was judged.

**The count line says whether any choice was left open**, so `<c>` is the
number of headings that end `— contested`, and it is written even when it is 0.

The inventory ships whatever the findings, so a reader can tell a clean diff from
one nobody looked at. **With no findings**, the line under the heading reads
`**No shape findings.**` and the inventory is open rather than folded, since it
is now the whole content. A filtered diff that is empty says so in place of the
table.

**The `**Not judged:**` line is present when Gather picked a file and absent
otherwise**, so a Ruby-only PR gets the comment it always did. With no findings
it sits under `**No shape findings.**`.

## 6 — Deliver

Your final message is the comment, starting at the `<!-- kit-shape-review -->`
line — no preamble, no closing remark, no surrounding fence. The marker is what
identifies the comment whoever's account posts it, and a clean body is what lets
a caller capture it or a person pipe it to `gh pr comment <n> --body-file -`.
