---
model: opus
---

Walk this project's spec suite, prove which examples can be removed, and file
them as one ticket. It decides; it never deletes.

**Arguments:** none. The scan covers the whole suite, every time. A scope
argument would make cheap runs possible and put the scoping decision on the
operator; a suite-wide answer is the one worth having, and the cost is the point
rather than a defect — expect tens of minutes.

`model: opus` is load-bearing. Subagents inherit the main-loop model, so this is
the tier every per-file pass runs at, and the axis is judgment-dense exactly
where a weaker tier fails: telling a tautology from a boundary case. A scan that
over-convicts deletes live coverage.

**`kit:rails-load-bearing-specs` is the axis, and it owns the output contract
too.** What convicts, what does not, and what a pass says are all its. This
command walks files and proves candidates; it does not restate a rule from that
skill.

---

## Step 1 · `enumerate` — Find the spec files

Every `*_spec.rb` in the project's spec directory, excluding fixtures, factories,
and support. Report the count before fanning out — it is what the run's cost is
proportional to, and it is the last cheap moment to stop.

**Refuse to start against a dirty working tree.** Step 3 mutates tracked files
and reverts them with git, which cannot distinguish its own mutation from work
you had in progress. Say what is uncommitted and stop.

## Step 2 · `assess` — One subagent per file

Fan out through the **Agent tool**, one agent per spec file, concurrently. Each
agent gets the file path and one instruction: apply `kit:rails-load-bearing-specs`
to this file and return its output contract — a line per convicted example, a
line per example a category reached and could not convict, nothing else.

**One file per agent, never a batch.** An agent holding several files reports on
the aggregate, and the aggregate is what the axis's unit rule exists to prevent.

**A file whose agent fails is unassessed, not clean.** Carry it into Step 5's
report by name. Silence about a file that errored reads identically to a file
with nothing in it, and the difference is the whole trustworthiness of a suite
sweep.

Collate the returned lines. Rank convicted candidates strongest first — tautology
above dead-code above contradiction, matching the axis's own convictability
order — and take the strongest band into Step 3.

**Ranking exists only to choose that band.** There is no report for it to order.
If the gate ever becomes cheap enough to run on every candidate, delete this
ranking rather than keeping it for shape.

## Step 3 · `witness` — Prove the shortlist

Deleting a spec produces a diff that cannot fail: the suite is green by
construction afterwards. So an executor has no signal at all unless this step
hands one down.

For each candidate in the band, one at a time:

1. Break the production code the candidate claims to cover — a returned value
   inverted, a guard removed, an argument dropped. One change, in one file.
2. Run only the examples claiming to cover it. Named files and examples; never a
   directory and never the suite.
3. Record whether anything went red, and what.
4. **Revert with `git checkout -- <file>`**, never by editing the file back. A
   re-edit is a second guess at what the original said; a checkout is the
   original.
5. **Confirm the revert with `git status`.** A file still modified aborts the
   whole run — say which file and what was done to it, and file nothing. A gate
   that cannot put the code back has stopped being a gate.

**A candidate whose mutation went red is not proven and is not a candidate** —
something noticed, which is the definition of load-bearing. Drop it, and say so
in Step 5.

**A candidate the gate could not prove stays unproven and never reaches the
ticket.** A spec nobody can prove is load-bearing is worth knowing about, and
Step 5 is where it is said.

The gate is expensive, which is why it runs on the band rather than on
everything.

## Step 4 · `file` — One ticket, or none

**A run that proved nothing files no ticket.** Say so in one line and stop.

Otherwise file exactly one issue carrying every proven example. Not one per
candidate: a prune is mechanical — delete these listed examples — so a ticket
each buys an executor nothing and costs a run each.

The ticket carries **`technical-debt`**. Its acceptance — behavior preserved
across the change — is vacuously true of a deletion, so the kind is not what
holds this ticket honest. The witness results are:

> Each listed example carries the mutation that went unnoticed, so the executor
> re-runs a check that can actually fail rather than observing that the suite is
> still green.

Follow `kit:writing-tickets` for the body, and give it the empty blocking marker
`<!-- kit-blocked-by: -->` so a sweep can see it.

**Never apply `ready-for-agent`.** That is a person's claim that a ticket is safe
to pick up unbidden, and this command filed it.

## Step 5 · `report` — Say what it found

The axis's output contract governs: a line per proven example, and nothing for
anything kept. Then the three things only a suite sweep can report, one line
each:

- Candidates the gate could not prove.
- Candidates the gate refuted — the mutation went red, so the example is
  load-bearing after all.
- Files that were not assessed, because their agent failed.

Close with the ticket number, or with the one line saying nothing was proven.

## Never

- Delete a spec, or edit any file outside a gate mutation you revert in the same
  step.
- Run a spec directory or the whole suite. The gate names examples.
- Convict from a call-site search. The axis refuses it, and this command's fan-out
  does not earn an exception.
- Add `ready-for-agent`, or a blocking marker naming issues.
