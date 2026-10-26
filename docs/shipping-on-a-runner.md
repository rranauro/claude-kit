# Shipping on a local runner

`plugins/kit/scripts/ship-startable.sh <label>` takes every startable ticket
under a label to an open PR, one at a time, until the label runs dry — run
directly by the operator in a terminal, left running or backgrounded, with no
cron and no cloud scheduling. What follows is what that gets wrong when it's
built the obvious way.

## Every ticket gets its own `claude -p`, never a loop inside one session

`/kit:ship-ticket` takes exactly one ticket per invocation on purpose — a
second ticket in the same conversation carries the first one's context through
its worktree setup, TDD, and PR, and degrades quietly rather than failing
loudly. `/loop`'s dynamic self-pacing doesn't fix this: it fires the same
conversation repeatedly with a scheduled wakeup between turns, which is still
one process and one context growing across firings. The runner instead shells
out to a fresh `claude -p "/kit:ship-ticket <n> unattended"` per ticket and
blocks until it returns — that block *is* the pacing, and it's why nothing
here sleeps between one ticket finishing and the next one starting.

## `--bg` keeps the process boundary and changes only the launcher

With `--bg`, every call runs as a `claude --bg` session, not a `claude -p`
call: an interactive session started in the background, billed the way any
interactive session is rather than as API usage, and one the operator can
`claude attach` to while it works. The runner still blocks on it, polling
`claude agents --json` until the session stops working, so the pacing and the
fresh-context-per-ticket guarantee above are unchanged.

Two things differ, and both are why the flag exists rather than a swap:

- **The grant has to be made the boundary on purpose.** `-p` refuses anything
  the grant does not allow. A background session falls back to the operator's
  permission mode. This runner's `--bg` path therefore pins
  `--permission-mode dontAsk`, which refuses anything the grant does not allow,
  the same as `-p` — so both paths here are bounded by the allow list. What is
  not bounded is a background session an operator starts by hand: that inherits
  whatever mode they are in, and auto mode approves commands the grant never
  listed. An allow list is a boundary only where the mode was pinned, which is
  why this runner pins it rather than trusting the default.

  A **deny** entry needs none of that care, because it holds in every mode. That
  is why the integration operations are denied rather than merely unlisted:
  `git merge`, `git rebase` and `gh pr update-branch` all name one operation, and
  closing only the git spellings leaves the GitHub one approved wherever auto
  mode is in force. No
  deny list reaches every equivalent, though — `gh api` is allowed and can merge
  a branch by itself — so `kit:ticket-loop`'s constraint that a denied operation
  stays denied however it is spelled is what actually carries the rule.
- **A finished session is `done` or `blocked`.** `blocked` means its last message
  read as asking for something. Nobody will answer, so the runner treats both as
  finished, reads the outcome from GitHub, and stops the session.

**A background session's answer comes back through a file, never its output.**
What it prints is a terminal recording, and its transcript's layout is Claude
Code's own and can change under the runner with any update. So the runner names
a file in a reply directory it creates, passes that directory with `--add-dir`,
and reads the file once the session stops: `/kit:list --offer-file` writes its
offer block there, and the same `offer_line` reads it. A file not written is the
unreadable reply below, not an empty backlog.

## The startable-ticket list has to be machine-readable, not ship-ticket's prose

`/kit:list <label>` exists so a script never has to parse `/kit:ship-ticket`'s
freeform Step 3 report to learn what's startable — it reads the same
`kit:startable-tickets` rule the sweep does and prints numbers a caller can
act on. The channel is the **offer block** `/kit:list` ends its output with, and
that command owns its shape.

The runner reads its own label's line there and no other text in the reply,
which makes three answers distinguishable where two used to be: a line with
numbers offers them, a line with nothing after the colon is a drained label, and
a missing block — or a block with no line for the label asked about — is a reply
the run cannot read, so it stops and says so. Scanning the whole reply instead
conflates all three, and it fails in the worst direction: the reply is written by
a model, the empty answer is where an explanation is most tempting, and a ticket
named in order to *exclude* it is exactly the number a scan then takes. A
mistyped label reaches the unreadable stop for the same reason, rather than
reporting a backlog nobody queried.

Halting a run over a formatting lapse is the deliberate half of that trade: a
halt carries its reason and can be resumed, where a wrong take opens a second
pull request against a ticket that already had one.

The runner re-asks it every iteration rather than working from a list
taken once at the start: a ticket blocked on another one in the same epic
doesn't become startable until the blocker's PR merges and closes it, which
happens well after that ticket's own `claude -p` call has already returned.

The same "don't parse the prose" reasoning applies a second time, to a
question `/kit:list` doesn't answer: whether a PR this run already opened is
still open. The runner tracks that itself, by diffing `gh pr list` state — never
by reading what the ship-ticket call printed.

It keys on GitHub's own closing-issue link, not on the `<issue>-` branch prefix
— `kit:startable-tickets` `already-carried` is the rule and carries the
argument. What the branch prefix costs *here* is a run's summary: a PR opened
from a branch that carries no issue number is invisible to a prefix scan, so a
ticket the runner shipped cleanly is reported as an anomaly, and the operator
goes looking for a failure that did not happen.

## Nothing startable right now is not the same as nothing left to do

An epic where merges are automated has a ticket that's blocked when the list
is read become startable minutes later, once its blocker's PR closes its review
round, goes green, and merges. Exiting the first time nothing is startable stops
in the middle of a dependency chain the run was about to drain. The runner tells
the two cases apart by what it's still waiting on: if any PR it opened this
run is still open, it polls and tries again: if none are, the epic is
actually done.

## `--observations` feeds a drained label one record at a time

With `--observations` (which implies `--bg`), a label with nothing startable is
fed from the observation store before the run polls or ends. One record is
filed, its issue is shipped, and only then is the next one filed. That order is
the point: filing every ready record at once is the backlog flood ADR 0008
rejects, and filing one ahead of the work leaves the tracker holding the queue.

- **What may be filed is decided by `observe.sh fileable`**, not by a model: a
  record waiting on a ticket whose check still gives its recorded answer, oldest
  first. A record waiting on the owner, one written before `waiting` existed,
  and one whose check has moved are the owner's triage and are never touched.
- **Filing is its own session, under its own grant.** `ship-settings.json`
  denies `gh issue create` to every ship pass, so `/kit:observe file` runs under
  `file-settings.json`, which can file one issue and write its reply and nothing
  else. It may decline a record an unattended run would foreseeably park. The
  record then stays in the store unchanged, and the run skips it until it ends.
- **The filed issue is shipped by number**, never offered to the sweep. It
  carries no `ready-for-agent` and no marker —
  `docs/adr/0009-a-filed-observation-is-shipped-by-number.md` says why.
- **The runner drops the record, and only once the issue has a PR or a park.**
  No session drops one. A ship result the run cannot trace would leave an issue
  nobody is carrying, so the runner parks it itself, in `kit:park`'s shape,
  before dropping the record. If that park cannot be written, the record stays.
- **A filed record counts toward `--max`; a decline does not.** The summary
  adds what was declined and why, and how many records are left — split by
  what each waits on, beside how many `fileable` last offered. A drain that
  files nothing looks like a flag that did nothing; the split says it was a
  store of `owner` records and records from before `waiting`, which a person
  marks with `observe.sh set-waiting` before a runner can take them.

A run killed between filing and dropping leaves both the issue and the record,
and the next run files the record again. That is accepted rather than guarded:
both are visible to the operator, and a crash is the case this runner already
leaves to the operator everywhere else.

## A silently-unresolved plugin command looks exactly like a clean run

`docs/tending-on-a-runner.md` names this failure for the CI gate — a pass
whose command doesn't resolve runs zero turns, exits fast, and reports
success. The same risk exists here: a `claude -p "/kit:list <label>"` or
`"/kit:ship-ticket <n> unattended"` call that returns in a few seconds with
nothing to show didn't find an empty backlog, it never ran. The runner floors
every call at a minimum duration and treats an under-floor return as a hard
stop, not a quiet "nothing startable" — the failure mode that's actually
dangerous to a run nobody is watching.

Unlike the CI gate, this runner constructs no `plugin_marketplaces`
registration, and nothing in the target repo decides whether `/kit:` resolves.
`ship-startable.sh` passes `--plugin-dir`, set to the plugin it lives in, on
every call — `-p` and `--bg` alike — because print mode does not load the
project setting source: however the kit reaches an interactive session against
that repo, a `claude -p` call never sees it, and `/kit:list` comes back
"Unknown command".

**So the kit a run ships with is the copy the script was launched from.** From a
clone, tickets ship on that clone's kit, not on whatever the target repo's
sessions have installed; launch it from the installed plugin's own `scripts/` to
keep the two the same. A run whose commands do not resolve is fixed at that
path, not in the target repo's settings.

Still worth a real smoke test against one ticket before trusting the runner
with a whole epic — the per-call minimum-duration floor above is the safety net
if a command does not resolve.

## The permission grant is broader than tending's, on the same split

`plugins/kit/scripts/ship-settings.json` is `tending-settings.json`'s
counterpart for shipping rather than reviewing — it grants `gh pr create`,
`gh issue edit` (for `kit-blocked` and `kit-hold`), and the git write commands
a full `kit:ticket-loop` pass needs, on top of everything tending already
grants. It must also grant `gh pr merge` and `gh pr edit`: `kit:ticket-loop`'s
final phase arms auto-merge itself and the review round writes its labels, so a
grant that withholds either leaves every shipped PR sitting green and unlabelled
with nothing downstream watching for it. An earlier split gave the merge to a CI
gate instead — a consuming project that has not installed one gets no merge at
all, which is the failure this grant now avoids. A held PR is armed only where
the project declares `## Hold check` (see `commands.md`). It must grant `gh pr ready` and the kit's own scripts too. `hand-off`
takes the PR out of draft with `gh pr ready` before arming, and a pass refused
it parks with a finished PR left in draft. The scripts are matched by a
`*/scripts/<name>.sh` wildcard because the `${CLAUDE_PLUGIN_ROOT}` a prompt
file names them by expands to a different absolute path in every install.
Worktree cleanup is granted only through `worktree-reclaim.sh`, never as a raw
`rm -rf .claude/worktrees/*` rule: a wildcard there also matches a path that
climbs out with `..`.
A consuming project's own
`--project-settings`
file merges its test and lint commands over this one before a run, the same
split `tending-settings.json` already uses — this file says what shipping a
ticket may do in any repo, the project's file adds how it verifies a change
before pushing.
A project that declares a `## Ship gate` in its `CLAUDE.md` grants that command
there too; the kit never grants it from the declaration. Ungranted, the gate
fails as a denied permission, which parks — so a project that declares a gate
without granting it has made every ticket park rather than installed a check.
A `## Screenshot capture` rule or `pr-screenshots` skill is granted the same
way: its command or browser tools in the project's file, never from the
declaration. An ungranted one does not park, and `kit:visual-pr` says what the
PR reports instead. The kit's default capture, for a project with neither, is
the one capture this file grants: `capture-page.sh`, by the same wildcard as the
other kit scripts. A runner session boots no server, so on a project that needs one, a
visual PR still reads "Not captured" until the project writes a skill that boots
it — with the reason being that no server answered, not a missing grant. Upload
stays unavailable on the runner: nothing here drives the operator's signed-in
browser, so the PR names the images' local paths.

## A crashed ticket needs no cleanup of its own

If a per-ticket call dies partway — the process is killed, the machine sleeps
— whatever worktree it left behind is exactly what a later
`/kit:ship-ticket` call's own Step 0 reclaim sweep picks up, because that
sweep runs unconditionally at the start of every invocation. The runner
doesn't track or clean up a dead worktree itself; a later ticket's own
startup does it for free.

*Later*, not next: the dead pass still holds the lease it took on that worktree
(`docs/worktrees.md`), and a sweep honours it until it expires. That is the price
of the lease being what stops a live pass losing its checkout — the two cases
look identical from outside, and the run that keeps working is the one worth
protecting. Nothing is lost meanwhile; the worktree is left exactly as it was.

## The safety valve is a hard cap, not a smarter startable check

If the startable rule is ever wrong in a way that makes the same ticket (or
an unbounded stream of tickets) look startable forever, nothing in the loop
detects that on its own — it isn't a judgment the runner is positioned to
make. The cap on tickets shipped per run is the answer instead: it stops the
run and says so, rather than trusting the check to catch its own failure.
