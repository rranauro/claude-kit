---
model: sonnet
effort: low
license: MIT — Copyright (c) 2026 Ron Ranauro, https://github.com/rranauro/claude-kit
---

Record what just surfaced as a checkable observation — and review what has
accumulated when you are ready to.

**Arguments:** `$ARGUMENTS` — bare, records the thing that just came up. `list`
reports what is in the store. `triage` walks it and clears it down. `file <slug>
--reply <path>` files one record as an issue, unattended, for the runner that
drains the store.

Invoke `observations` via the Skill tool first. It owns the record shape, the
store's location and the triage protocol; this command is the human entry point
to them. A producing pass calls that skill directly and never this command.

---

## Bare — record what surfaced

You are working, and a second thing walks into the room. It is real, it matters,
and it has nothing to do with what you are holding. Chasing it loses the thread;
saying "we should think about that" loses the thing.

**Name what you are recording and let the user correct you before writing.**
Where the session holds more than one candidate, say which one you took.
Recording the wrong thing is worse than recording nothing, because it reads as
handled.

Then fill the record the skill defines, **claim before check** — that order is
this command's own, and it is what makes the pair hold. Writing the check second
lets it push back: a claim no cheap command can test is a claim that has not been
stated sharply enough yet, and the fix is to sharpen the claim rather than to
reach for a heavier check.

Append it with `${CLAUDE_PLUGIN_ROOT}/scripts/observe.sh`, report the line it prints, and
**return to what you were doing**. The interruption ends here; that is the entire
point.

---

## `list` — what is in the drawer

```
${CLAUDE_PLUGIN_ROOT}/scripts/observe.sh list
```

One line per record and the store's size. Nothing counts it on a schedule, so the
size is why this mode prints at all — the drawer opens when someone remembers it
exists, and the one time it does has to say how full it got.

Report it and stop. Listing decides nothing.

---

## `triage` — review it and clear it down

Run the skill's triage protocol. Its shape in one line: `${CLAUDE_PLUGIN_ROOT}/scripts/observe.sh recheck` bins
every record by whether its witness still holds, and the user decides each bin
before `${CLAUDE_PLUGIN_ROOT}/scripts/observe.sh drop` clears it.

**This is its own pass, on its own invocation.** Triage against a session already
carrying a ticket is the thing the store exists to prevent, arriving from the
other direction.

---

## `file <slug> --reply <path>` — one record, filed for the runner

`plugins/kit/scripts/ship-startable.sh --observations` starts this in a
background session of its own, once per record, after `observe.sh fileable`
offered the slug. Nobody is watching, and nothing here asks. The runner ships
what you file and drops the record itself; this mode never drops one, and its
grant refuses it.

**The reply is the whole outcome.** Write exactly one line to `<path>` with the
Write tool, and nothing else — the runner reads only its first line:

```
filed: <issue-number>
```

```
declined: <the reason, in one sentence>
```

A reply not written reads as a decline. So does any other first line.

**1 · Read the record:** `${CLAUDE_PLUGIN_ROOT}/scripts/observe.sh show <slug>`.
Re-run `${CLAUDE_PLUGIN_ROOT}/scripts/observe.sh recheck <slug>` and decline
unless it says `holds`: the store may have moved since the runner asked.
Decline too if the record does not wait on a ticket.

**2 · Decline what an unattended run would foreseeably park.** The ticket you
file is shipped next by `/kit:ship-ticket <n> unattended`, with no one to answer
it, and a park after filing leaves the backlog holding an issue that never
needed to exist. Decline, naming which, when:

- **You cannot state acceptance criteria and what is out of scope** from the
  record and the code. `/kit:design unattended` parks on exactly that.
- **The work reaches what `/kit:design` *Park on* names** — a scope change the
  record does not settle, a constraint its criteria cannot bound (security,
  tenancy, anything destructive, a migration needing production reconciled), or
  criteria that would not be buildable or testable once the code is open.
- **The premise is gone** — the code the claim is about has moved on in a way
  the check does not see. Read the files the claim names before filing.

**An approach left open is not a reason to decline.** `/kit:design unattended`
compares approaches and breaks ties itself, so a record whose `decision` names
the destination but not the route is one it can design.

A decline leaves the record in the store, unchanged, for the owner's triage.
That is a fine outcome, not a failed one. Do not soften a reason to get it filed.

**3 · File it.** Draft the issue with `kit:writing-tickets`, write its body
with the Write tool to `<reply path>.body.md` — beside the reply, the one place
this session may write, since a shell redirect or heredoc is refused — and
`gh issue create --body-file <reply path>.body.md`. Never pass the body inline:
don't-ask mode refuses a quoted argument holding a line that starts with `#`,
so every body with a heading is refused. A reader of the issue must need nothing from the store, so the
body carries, verbatim and under their own headings, the record's `surfaced`
thread and its `decision`, beside the claim and the check that tests it. Give it
the kind label that fits, in the project's spelling (`kit:project-rules`
*Labels*), since hand-off reads the kind.

**Add no `ready-for-agent` and no `kit-blocked-by` marker.** The runner names
the issue to `/kit:ship-ticket` itself, which needs neither, and a ticket
marked startable is one every other sweep on the label could take —
`docs/adr/0009-a-filed-observation-is-shipped-by-number.md` says why.

**4 · Reply** `filed: <n>`, and stop.
