---
model: sonnet
---

Record what just surfaced as a checkable observation — and review what has
accumulated when you are ready to.

**Arguments:** `$ARGUMENTS` — bare, records the thing that just came up. `list`
reports what is in the store. `triage` walks it and clears it down.

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

Append it with `plugins/kit/scripts/observe.sh`, report the line it prints, and
**return to what you were doing**. The interruption ends here; that is the entire
point.

---

## `list` — what is in the drawer

```
plugins/kit/scripts/observe.sh list
```

One line per record and the store's size. Nothing counts it on a schedule, so the
size is why this mode prints at all — the drawer opens when someone remembers it
exists, and the one time it does has to say how full it got.

Report it and stop. Listing decides nothing.

---

## `triage` — review it and clear it down

Run the skill's triage protocol. Its shape in one line: `observe.sh recheck` bins
every record by whether its witness still holds, and the user decides each bin
before `observe.sh drop` clears it.

**This is its own pass, on its own invocation.** Triage against a session already
carrying a ticket is the thing the store exists to prevent, arriving from the
other direction.
