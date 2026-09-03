---
model: sonnet
---

Report the open tickets a sweep would actually start.

**Arguments:** `$ARGUMENTS` — one or more labels. With none, the whole backlog.

The issue list in a browser shows every open ticket under a label. It cannot say
which of them an agent may pick up, so working that out means opening tickets one
at a time. This command answers it and stops — creating nothing, starting
nothing, touching no worktree.

Its whole output is numbers and titles you can hand straight to
`/kit:ship-ticket <number>`.

## Step 1 — Classify

Invoke `kit:startable-tickets` via the Skill tool. It owns what startable means,
which is what makes the guarantee here hold: a ticket this command names is one
`/kit:ship-ticket <number>` will in fact start.

**Several labels are one classification, not one per label.** The skill's
candidate query already returns each ticket's labels, so run it once without
narrowing and partition the result by label afterwards. Running it per label
re-fetches every ticket carrying more than one of them, and re-resolves the same
blockers and worktrees each time.

**Validate the names first** — one `gh label list` covers all of them, where
discovering a typo from a failed query costs a round trip each.

## Step 2 — Report

Per label, its startable tickets by number and title, lowest number first.
Nothing else — no reasons, no ranking, no recommendation about which to take.
Explaining an omission is `/kit:ship-ticket`'s job, because it was going to start
one; answering the wider question here buries the list under prose about tickets
you cannot act on.

```
ready-for-agent + bug
  #52  Reconcile the webhook retry window
  #58  Stop the importer swallowing a 409

ready-for-agent + technical-debt
  nothing startable

ready-for-agent + user-experence
  no such label — did you mean `user-experience`?
```

The last two lines are different answers, and only one of them is a typo.
