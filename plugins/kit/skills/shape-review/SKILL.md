---
name: shape-review
description: Judge the object shape a pull request introduces — its new classes, signatures and call sites, scored on kit:rails-codebase-design with placement included — as one Markdown comment a person can post as written. Use when a PR's author was an unattended agent, when asked to review a diff's shape or placement, or when another skill needs a shape review of a PR.
---

# Shape Review

Judge what one pull request's diff introduces, on `kit:rails-codebase-design`.
**Placement is in scope** — `kit:visual-review` leaves it to the author; this
skill judges it, because the author it reviews is usually an unattended agent
whose design nobody argued with.

**Change nothing.** No label, no commit, no push, no post, no file in the
working tree. The comment is the whole output, and posting it is the reader's
decision.

**Argument:** a pull request number.

## 1 — Gather

Fetch the PR head once and do every read, diff and grep locally against it:

```bash
gh pr view <n> --json headRefOid,baseRefOid
git fetch origin pull/<n>/head        # lands in FETCH_HEAD; creates no branch
git diff <base>...<head> -- '*.rb' '*_controller.js'
git show <head>:<path>                # a whole file, when a hunk cannot say what a method reads of self
```

Cite `file:line` at the head SHA.

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
exception, and a caller holds the PR on it, so never call a finding contested to
be thorough.

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
order here would make it for them. Its **Costs** gives each After its own line:
the call sites outside the diff that move, counted, since reach is all that is
left to separate them.

**An accreted interface finding leaves out the panels.** Its subject is the
object, and the reshape is decided by whoever takes it up, so an **After**
here would be a design nobody asked this pass for. **Call site now** is the first
added member's caller, or its definition when it has none, and any other members
the diff added there are listed in **Costs**. **Costs** names each existing
single-caller member with its one caller — or its definition, when it has none —
and the commit that introduced it — `` `#removed_fields` (`jobs/purge.rb:14`, a1b2c3d Purge removed fields) ``.
It goes in **Costs** because `kit:review-copilot` carries that line and would
drop a new one.

Order findings strongest first: contested findings above the rest, since a
caller holds the PR on them; then a placement finding above a naming one, a
count with several callers above one with one.

## 5 — The comment

````markdown
<!-- kit-shape-review -->
## Shape review — #<pr> at `<short sha>`

**<n> findings, <c> contested**

### 1. <count name> — `<Class#method>` — contested

**Call site now** (`<file:line>`)
```ruby
<the line as the diff writes it>
```

**After — <move>**
```ruby
<the panels, as below>
```

**After — <another move>**
```ruby
<the panels, as below>
```

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

**The count line is what a caller reads to decide the hold**, so `<c>` is the
number of headings that end `— contested`, and it is written even when it is 0.

The inventory ships whatever the findings, so a reader can tell a clean diff from
one nobody looked at. **With no findings**, the line under the heading reads
`**No shape findings.**` and the inventory is open rather than folded, since it
is now the whole content. A filtered diff that is empty says so in place of the
table.

## 6 — Deliver

Your final message is the comment, starting at the `<!-- kit-shape-review -->`
line — no preamble, no closing remark, no surrounding fence. The marker is what
identifies the comment whoever's account posts it, and a clean body is what lets
a caller capture it or a person pipe it to `gh pr comment <n> --body-file -`.
