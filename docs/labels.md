# A label is a claim about a record

Every label this kit writes is a cheap stand-in for something expensive to
read. `kit-review-closed` stands for the summary comment. `kit-hold` stands for
the reason in that summary, or for a person's decision at triage. `kit-blocked`
stands for the "Blocked by" section a park wrote. `kit-pinned` stands for an
observation and the round summary beside it.

A label without its record is therefore not a partial success. It is the one
state that suppresses every later look: the PR reads as handled, no gate re-runs
it, and what was decided is unrecoverable. Both rules below are about writes;
how a *reader* should treat the split is `tending-on-a-runner.md`'s.

## Write the record, then the mark — and only then

The mark is conditional on the record. A pass whose record did not land has not
done the thing the label claims, so it does not apply the label, and it reports
what failed rather than completing.

Failing that way costs a later firing that finds the work already done. Failing
the other way costs the decision itself. There is no ordering where both are
cheap, so the kit always pays the recoverable one.

The exception proves the rule rather than bending it: `/kit:review-copilot`
applies `kit-pinned` *before* appending its observation, because on a runner the
observation store lives in a checkout the job discards while the round summary —
already posted, already conditional — carries the reasoning. The record exists;
the append is a second copy.

## A mark that will not apply is reported, never skipped

A pass can apply a label that already exists and cannot create one that does
not: `ship-settings.json` and `tending-settings.json` both deny
`Bash(gh label:*)`. So the first repo to adopt a newly defined label gets a pass
that decides correctly and silently records nothing.

Keeping the deny is deliberate — an unattended pass may not invent repo-wide
vocabulary. What changes is that the failure is spoken. A pass that could not
apply a label says which label and why, in the same breath as the decision it
was recording, so the reader knows the decision stands without its mark. Never
treat a rejected `gh pr edit --add-label` or `gh issue edit --add-label` as a
no-op, and never create the label to get past it.

The fix is one command, and it belongs to whoever owns the repo:

```
gh label create kit-review-closed
gh label create kit-hold
gh label create kit-blocked
gh label create kit-pinned
```

## Finding the repos already in this state

A label written before this rule existed left no trace to grep for.
`plugins/kit/scripts/audit-review-records.sh` names the PRs carrying
`kit-review-closed` with no record comment. It exits non-zero when it finds one,
and costs one API call whatever the PR count, so a project can wire it into a
gate rather than remembering to run it.
