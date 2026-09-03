---
model: sonnet
---

Report the open tickets a sweep would actually start.

**Arguments:** `$ARGUMENTS` — one or more labels. With none, the whole backlog.

The issue list in a browser shows every open ticket under a label and answers a
different question: whether an agent can start one. This command answers that
one, and stops. It creates nothing, starts nothing, and touches no worktree.

Run it from anywhere. Its whole output is a list of numbers and titles you can
hand straight to `/kit:ship-ticket <number>`.

## Step 1 — Classify

Invoke `kit:startable-tickets` via the Skill tool, once per label given, and once
with no label if none were.

**That skill owns what startable means, and this command must not restate it.**
The one guarantee worth having here is that a ticket this command names is one
`/kit:ship-ticket <number>` will in fact start — which holds only while both read
the same rule. When the definition changes there, this command's output changes
with it and nothing here is edited.

## Step 2 — Report

Per label, its startable tickets by number and title, lowest number first.
Nothing else — no reasons, no ranking, no recommendation about which to take.

```
ready-for-agent + bug
  #52  Reconcile the webhook retry window
  #58  Stop the importer swallowing a 409

ready-for-agent + technical-debt
  nothing startable
```

**A label holding nothing startable and a label nobody created are different
answers.** `gh` errors on an unknown label rather than returning an empty list,
so say which happened:

```
ready-for-agent + user-experence
  no such label — did you mean `user-experience`?
```

**Explaining an omission belongs to `/kit:ship-ticket`.** It reports why a
candidate was skipped because it was going to start one; this command was asked a
narrower question, and answering the wider one buries the list under prose about
tickets you cannot act on. The browser is where the full backlog lives.
