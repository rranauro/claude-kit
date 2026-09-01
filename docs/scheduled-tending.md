# Running the janitor on a schedule

`/kit:tend-prs` is written to run with nobody watching, and inside a session it
mostly doesn't run at all — it only fires if you remember to start it, and
killing it costs you whatever else that session was doing. Two scripts move it
out of session.

## Install

The scripts live in this checkout and are run from it by path — nothing is
copied anywhere on install, so use an absolute path if your shell is somewhere
else, and name the repo you mean with `--repo-dir`. It defaults to the current
directory, which is rarely the repo you want tended.

```
KIT=~/dev/claude-kit/plugins/kit/scripts   # wherever you cloned this

$KIT/install-tending.sh --repo-dir ~/dev/yourproject             # every 10 minutes
$KIT/install-tending.sh --repo-dir ~/dev/yourproject --interval 30
$KIT/install-tending.sh --repo-dir ~/dev/yourproject --status    # loaded? what did the last pass do?
$KIT/install-tending.sh --repo-dir ~/dev/yourproject --uninstall # unload and remove
```

`--interval` takes minutes and defaults to 10. Reinstalling over an existing
agent is how you change it — the install unloads the old one first, so there is
no separate edit step and no stale plist left loaded.

It writes a launchd agent labelled by the repo it tends, so tending two
checkouts is two installs and removing one leaves the other alone. launchd
rather than cron because it survives logout and catches up after sleep; not
cloud scheduling, which cannot work here at all — the pass needs the real
worktrees and your local `gh` and `claude` credentials.

`tend-prs.sh` is what the agent runs, and running it by hand is how you watch a
pass before handing it over.

## Why it's a script and not a one-line `claude -p`

### The permission grant is a file you can read

`tending-settings.json` enumerates what the pass may do, and the run loads no
other settings source — `--setting-sources ''` — so the boundary is that file
rather than whatever your `~/.claude/settings.json` happens to allow this month.
Headless means nothing can be approved interactively, so a call the grant doesn't
cover fails and lands in the report; the command is told to record a denial and
carry on, never to route around one.

Worth being precise about what it does and doesn't control, because the obvious
reading is wrong. **Read-only commands are auto-approved by the CLI's own
classifier and cannot be narrowed** — `ls` runs whether or not it appears in the
allow list, under every permission mode. So the allow list is not an exhaustive
inventory of what a pass can execute. What it *is* exhaustive about is writes:
an unlisted side-effecting command is refused outright. That's the boundary that
matters — what an unwatched job can change, not what it can look at. The deny
list is load-bearing for the same reason: `git push` has to be allowed for the
triage step to push fixes, which would otherwise carry `git push --force` along
with it.

### A pattern's prefix has to end on a token boundary

`Bash(<prefix>:*)` is matched against the command's arguments, not against its
raw text, so a prefix that stops mid-argument matches nothing at all — ever.
`Bash(gh api repos/:*)` looks like "any repos API call" and is really "an
argument equal to `repos/`", which no invocation produces. `Bash(git rev-parse:*)`
works because its prefix ends on an argv token boundary, after `rev-parse`. The
failure is silent and one-directional: the entry sits in the allow list looking
correct while every call it names is refused, and unattended is exactly where
nobody is watching to notice. Test a new entry by running the pass by hand before
trusting it. (Verified against Claude Code 2.1.232 — this is harness behavior,
not a documented interface, so re-check it if patterns start failing after an
upgrade.)

### And it has to match from the first token

A global flag between the binary and its subcommand displaces everything after
it, so `Bash(git status:*)` does not cover `git -C <path> status --porcelain` —
the second token is `-C`, not `status`. Allowing `Bash(git -C:*)` would fix that
call and every other one: `git -C <path> push --force` would pass too, because
the deny entries fail to match the `-C` form for exactly the same reason. So the
grant cannot express this safely. Swapping it for `cd <worktree> && git status`
does not help either, which is what the commands tried first: the first token is
then `cd`, so that form is unmatched too, and the obvious repair — a `Bash(cd:*)`
prefix — matches a compound command and leaves every deny entry one `&&` away
from being bypassed. Interactive commands may still use `-C`, where a human is
present to approve.

The rule also constrains what a grant can express, and not always kindly.
`Bash(osascript -e display notification:*)` is broken for the same reason — the
whole AppleScript program arrives as one argument — so the notification an
escalation fires is currently refused. There is no narrower pattern that fixes
it: `Bash(osascript -e:*)` matches, but `osascript -e` accepts
`do shell script "…"`, which routes around every deny entry. Widening it would
trade a dead notification for a general shell escape. The fix is to stop asking
the agent to notify at all — the runner is plain bash and unconstrained by the
grant — and that is tracked separately rather than bolted on here.

`idle-check` is the same shape and is already fixed that way. Deciding whether a
worktree is free to write to means reading `git status` and `lsof` for a path that
is not the agent's cwd, which no grantable pattern covers. So `tend-prs.sh`
surveys every linked worktree before it invokes `claude -p` and passes the
verdicts in as `<path> <branch> <idle|busy> <reason>`; the pass reads them instead
of proving them. Attended runs still derive it themselves. The general lesson is
worth stating plainly: when the grant cannot express a check, move the check to
the runner rather than widening the grant to fit it.

### The pass reads its commands off disk

A headless `claude -p` doesn't load plugin commands the way an interactive
session does, and the Skill tool resolves `skills/`, not `commands/` — so "invoke
`/kit:review-copilot` via the Skill tool" fails with *Unknown skill* every time.
The runner points the pass at the command files instead, resolved from the
script's own location rather than from `--repo-dir`, because the kit and the repo
being tended are different checkouts: tending `~/dev/zcommerce` reads its
commands from wherever the kit lives.

## Holding a PR back

Add the **`kit-hold`** label from the GitHub UI and the pass takes no action on
that PR at all — no triage, no auto-merge, no worktree removal — and reports it
as held. It works from a phone with no checkout, which is the case it was built
for: walking a change in the running app takes as long as it takes, and the
worktree has to still be there when you finish. A merged PR that still carries
the label keeps its worktree too.

The pass never applies the label and never removes it. `gh pr edit` and `gh label`
are on the deny list, so the direct routes are closed by the grant rather than by
good behavior. `gh api` is not similarly constrained — it is allowed wholesale,
because a path-scoped pattern cannot match at all (see the token-boundary note
above), and nothing distinguishes a read from a write through it. So that one
back door rests on the command, not the grant. Take the label off and the PR is
handled normally on the next pass, with no residue: `held` is read fresh from the
label every firing and stored nowhere.

Create it once per repo with `gh label create kit-hold`.

**The decision usually gets made earlier than the PR.** `/kit:triage` and
`/kit:design` both ask whether the downstream PR will need holding — at the
moment they settle the ticket, which is when you actually know — and record the
answer on the issue. `/kit:new-pull-request` transcribes it onto the PR at
creation, so a PR can be born held. Without that, holding means racing a
scheduled pass: the agent opens a PR, tending fires within minutes, and the label
you always intended to apply arrives after the merge was already enabled. The
question defaults to no and takes one keystroke to decline.

## Concurrency

**Two passes can't act on the same PR.** Derived state makes overlap harmless in
general, but two concurrent triages of one PR is a double push. The lock is an
atomic `mkdir` holding the pid — macOS has no `flock` — and a pass killed
mid-flight leaves a directory that the next pass reclaims only after checking
the recorded pid is actually gone.

## Reading what happened

**Every pass leaves a record**, and `--status` is how you read it:

```
$KIT/install-tending.sh --repo-dir ~/dev/yourproject --status
```

That prints whether the agent is loaded and then the **whole of the last pass**,
cut at its own start marker rather than by line count — a quiet pass is a handful
of lines and a busy one is fifty.

Two kinds of line share that file, and it is worth knowing which you are reading.
The runner writes the merge side itself — `main sync:`, `cleanup:`, `teardown:`,
`idle survey:` — so those appear on every firing whether or not a model ran, and
a firing that ends `pass end ok (no model needed)` is the gate reporting there was
no judgment work. Everything else is the model's Step 7 report, printed only on
the firings that started one. So a worktree removal shows up as a `teardown:` line
rather than in a report.

Underneath it is one appended file per repo,
`~/.claude/logs/tend-prs/<owner>-<repo>.log`, so `tail -f` follows a run live and
reading a week at once is how you notice the worktree that has been dirty since
Tuesday. Skip reasons are in there by design. Read it rather than waiting to be
pinged: escalations are *meant* to fire a notification and quiet passes to stay
silent, but the grant entry that would allow one cannot match (see the
token-boundary note above), so today nothing fires either way.

## Project-declared gates

The triage step runs the project's tests and linter, and those commands are
whatever that repo's `CLAUDE.md` says they are — the kit cannot know them, and
baking a guess in would hand every repo `bundle exec` to buy one repo its gates.
Put the additions in `<main-checkout>/.claude/tending-settings.json` and they are
merged over the kit's grant at run time:

```json
{ "permissions": { "allow": ["Bash(bundle exec rspec:*)", "Bash(bundle exec rubocop:*)"] } }
```

Only `allow` is worth putting there: deny beats allow in the merged file, so a
project can widen what a pass may run but cannot unlock anything the kit refuses
— which matters, because that overlay lives in a repo the pass can write to. A
malformed overlay is ignored with a warning rather than failing the pass; a
scheduled job should not stop running over a typo.

## What a firing costs

Most firings cost no model at all. `tend-prs.sh` does the mechanical half of the
pass itself, in plain bash, before deciding whether to start one: it
fast-forwards `main` where that is safe, removes the worktrees and branches of
merged PRs, and surveys what survives for idleness. None of that needs judgment
— a merged PR is a fact GitHub reports, a worktree either matches its branch or
does not, and `kit-hold` is a label read rather than weighed.

Then it asks whether anything is left that does. Three things start a model:
reviews have landed with no triage marker, a check is failing on a PR not yet
escalated, or the marker is present but auto-merge is off. Nothing else does.
A quiet firing reaches that verdict in a few seconds of `gh` calls and exits.

This is why the interval can be short. Before the gate, every firing spent a
full context — re-reading `tend-prs.md` and its delegates, ~5.8k tokens of
instructions before any tool output — and roughly two thirds of them did so to
print a line saying nothing happened. Polling faster still buys nothing on the
work that matters (Copilot lands 3–5 minutes after a PR opens, `classify`
deliberately waits for both reviewers, and since `/kit:run-ticket` split out no
downstream work waits on a pass), but the cost of guessing the interval wrong in
the fast direction is now small.

The gate over-approximates on purpose: a false yes costs one quiet pass, while a
false no would strand a PR forever. It answers "could there possibly be work
here", never "what is the work" — every rule about what actually happens to a PR
stays in `tend-prs.md`, so there is no second copy to drift.

## On sonnet

`tend-prs.sh` passes `--model` to the headless run, and **that flag is the only
thing that sets the model.** The `model: sonnet` frontmatter in `tend-prs.md` and
`review-copilot.md` has no effect on a scheduled pass: the runner points the pass
at those files to *read*, because plugin commands do not load under `claude -p`
and the Skill tool resolves `skills/` rather than `commands/`, so nothing ever
parses their frontmatter. It governs attended use, and the runner's default
matches it so the two do not disagree — but if you want a different model
unattended, `--model` is the lever, and editing the frontmatter will appear to do
nothing.

Sonnet is the right default because the model is not the deliverable here, unlike
`pr-review.sh`. The one judgment-heavy step is verifying review findings against
the code, in `/kit:review-copilot`.

A pass killed partway is safe by construction, and this is the property to
preserve when changing any of it: all state is derived from GitHub and git, and
the triage marker is written last, so a firing that dies mid-triage is
re-triaged rather than mis-classified as done.
