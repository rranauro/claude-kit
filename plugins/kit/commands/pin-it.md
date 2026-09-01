---
model: sonnet
---

Park a requirement that surfaced mid-work but isn't ready to be discussed — and bring one back when it is.

**Arguments:** `$ARGUMENTS` — optional. Bare, pins the thing that just came up in this session. `list` reports what's pinned. A slug (or a fragment of one) resurfaces that pin and triages it.

---

## What a pin is for

You're debugging, and a second requirement walks into the room. It's real, it
matters, and it has nothing to do with what you're holding. The two bad options
are to chase it — losing the thread you were on — or to say "we should think
about that" and lose it entirely by the end of the session.

A pin is the third option. It costs one command, states no position, and asks
nothing of you now.

That last part is what separates it from `/kit:architect`. An issue asks you to
have a decision; the whole premise of a pin is that you don't have one yet.
Which means the pin store has to be cleared down, or it becomes a drawer of
half-thoughts — hence `list`'s staleness flag and the rule that resurfacing
either acts on a pin or deletes it.

---

## Where pins live

`<main-repo-root>/.claude/pins/<YYYY-MM-DD>-<slug>.md` — **always the main
checkout**, never the worktree you happen to be standing in.

This is not a detail. Pins are created mid-debug, and mid-debug you are in a
ticket worktree. A pin written there dies with `/kit:cleanup-worktree` — the
requirement evaporates at the exact moment the ticket ships, which is the moment
you were relying on it to survive. Resolving to the main root also means `list`
shows every pin no matter which worktree you invoke it from.

Resolve the path, don't assume it:

```bash
common=$(git rev-parse --git-common-dir)
case "$common" in /*) ;; *) common="$(git rev-parse --show-toplevel)/$common" ;; esac
pins="$(dirname "$common")/.claude/pins"
```

`--git-common-dir` points at the *main* repo's `.git` from inside any worktree,
which is the whole reason to use it over `--show-toplevel`.

### Keeping them unversioned

Pins are private working notes, and many projects commit `.claude/` — so an
ignore rule in `.gitignore` would itself be a tracked change, and one that
shows up in every PR diff.

Put the rule in `.git/info/exclude` instead. It's per-clone, untracked, and
invisible to everyone else. Check before writing, and only write once:

```bash
git check-ignore -q .claude/pins || echo '.claude/pins/' >> "$common/info/exclude"
```

Note this is the *common* dir again — a worktree's own `info/exclude` would not
apply to the main checkout.

---

## Mode 1 · pin (no arguments)

### Step 1 · `identify` — Name what's being pinned

Look back over the session for the thing that surfaced and got deferred. Usually
it's the most recent "that's a good point, but not now" — but if the session has
more than one candidate, **say which one you're pinning and let the user
correct you** before writing anything. Pinning the wrong topic is worse than not
pinning, because it reads as done.

If nothing in the session looks like a deferred requirement, ask what to pin
rather than inventing one from the general subject matter.

### Step 2 · `cull` — Write the pin

A pin is not a transcript dump. It's worth exactly what it saves you from
re-deriving, which is a much smaller set of things than the conversation
contains.

```markdown
# <one-line statement of the requirement, in the user's own framing>

**Pinned:** <YYYY-MM-DD> · from <branch or issue #, if any>

## Why it surfaced
<The thread that exposed it — what we were doing when it came up, and what
about that work made this visible. This is the part that is genuinely
unrecoverable later; everything else can be re-derived from the code.>

## What we already know
<Evidence gathered: file paths, symbol names, behavior observed, constraints
established. The expensive part. Paths only — no line numbers.>

## Ruled out
<Anything already considered and rejected, with the reason. Omit if nothing was.>

## Still open
<What's unknown, and why this wasn't ready to discuss. If the reason was
"we were in the middle of something else", say that — it's a valid reason and
it tells the reader the topic may need no more than a decision.>
```

Two things a pin must **not** contain:

- **A plan, or a file-and-line implementation sketch.** Same rot argument as
  `kit:writing-tickets`: the repo drifts, the sketch goes wrong quietly, and
  the reader trusts it. Whoever resurfaces this re-explores the current code.
- **Line numbers.** Paths and symbol names survive a refactor; line numbers
  don't, and a stale one sends the reader to the wrong place confidently.

Slug from the requirement, kebab-case, a few words. Write the file, confirm the
path in one line, and **return to what you were doing** — the entire point is
that the interruption ends here.

---

## Mode 2 · `list`

One line per pin, oldest first:

```
2026-07-02  theme-preview-caching     · previews go stale after a brand edit   [STALE · 41d]
2026-08-09  csv-import-partial-rows   · what happens to rows 3..n when row 2 fails
```

Flag anything older than **30 days** as stale with its age. Don't delete stale
pins automatically — a pin the user has walked past for a month is either dead
or the most important thing in the drawer, and only they know which. Offer to
resurface the stale ones for triage.

If the directory is empty or missing, say so in one line. Don't create it.

`/kit:tend-prs` `report` prints the same count — outstanding, and stale by name
— on every firing. That's the passive half: `list` is what you run when you
remember pins exist, and the tend-prs line is what tells you when you don't. It
only counts; triage happens here, in a session with someone in it.

---

## Mode 3 · resurface (`<slug>`)

### Step 1 · `load` — Read it back, then re-check it

Match the argument against pin filenames; if it's ambiguous, list the matches
and ask. Read the pin in full and summarize it back — the requirement, why it
surfaced, what's open.

Then **verify the evidence before building on it**. A pin is a snapshot of a
repo that has since moved: confirm the files and symbols it names still exist
and still behave as described. Say plainly which parts still hold. A pin whose
premise has been fixed in the meantime is a valid outcome — that's a `drop`.

### Step 2 · `triage` — Four outcomes, and three of them delete the pin

- **File it** — the requirement is clear enough to state as a problem and a
  desired outcome. Run `kit:writing-tickets`. Carry across the *why it surfaced*
  section verbatim; that's the context an issue written from scratch would lack.
  Note the issue number back, **delete the pin**.
- **Do it now** — small, located, and you're in a position to. Route it through
  whatever session shape applies (`kit:start-ticket` for its own branch,
  `/kit:polish-ticket`'s `triage` if you're already on a cleanup branch).
  **Delete the pin** once the work is committed, not when it's started.
- **Drop it** — no longer real, already fixed, or the user decides against it.
  **Delete the pin.** Say in one line why, so a re-pin of the same idea later
  isn't a surprise.
- **Re-pin** — still not ready, but you learned something. Rewrite the pin with
  what the re-check turned up and update the `Pinned:` date. This is the only
  outcome that keeps a file, and it should be the rare one. Two consecutive
  re-pins of the same topic means it's really a ticket, or really a drop — say
  so.

Never leave a resurfaced pin untouched. A pin that survives triage unchanged is
just a stale one with a fresher read on it.

---

## Failure / interrupt handling

- **Invoked from a worktree.** Expected — it's the common case. The path
  resolution above already handles it; confirm the pin landed under the main
  checkout, not the worktree.
- **`.claude/pins` is tracked in this repo.** Someone committed a pin before
  the exclude rule existed. Say so and ask — untracking it is a real change to
  their repo, not a cleanup to do quietly.
- **The session was compacted before pinning.** The *why it surfaced* section is
  the casualty, and it's the one that matters. Say the pin is thin on
  provenance rather than reconstructing a plausible-sounding origin story.
