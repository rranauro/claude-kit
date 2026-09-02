# A branch is deleted on what the remote received, not on local ancestry

Every cleanup path in the kit deleted branches the same way: `git branch -d`
first, and on refusal `git branch -D`, silently, on the grounds that the PR had
been verified merged and the refusal therefore meant a squash-merge.

That refusal has two causes. A squash-merge collapses the branch's commits into
one new commit, so the originals are unreachable from every remote ref. Work that
was committed and never pushed is unreachable from every remote ref for the
obvious reason. The two are indistinguishable locally — `git rev-list <branch>
--not --remotes` separates them no better than `-d` does — so the escalation was
a coin toss that destroyed the second case.

We decided the test is what the remote received: a merged or closed PR whose
`headRefOid` equals the local tip, or, for a branch that never had a PR, a tip
present on a remote ref. Anything else keeps its branch and reports it. Because
that is a positive check rather than an inference, it holds with nobody watching,
which is what lets an unattended pass delete branches at all.

## Considered Options

**Keep `-d` and narrow the escalation.** The obvious repair, and it cannot work:
no local test separates the two cases, so any narrowing is a better-informed
guess at the same coin toss.

**Never delete branches.** Safe, and it was seriously considered. It leaves a
dead local branch per shipped ticket and makes the accumulation invisible, which
is the failure mode that produced the escalation in the first place.

**Reclaim directories unattended but only report deletable branches.** The
conservative version of what we shipped. Rejected because the remaining risk was
in the inference, not in the absence of a human — once the test asks the remote,
a person adds no information to it.

## Consequences

A branch is now kept in cases the old code deleted: an open PR, a merged PR with
commits added after the merge, a never-pushed spike, and any run where GitHub
could not be reached. Every one of those is reported by name with its reason,
because a kept branch nobody is told about accumulates exactly as silently as the
dead ones did.

Deleting a branch also now costs a network round trip per branch. Batching the
query across branches was rejected: it needs a `--limit` window, and a branch
whose PR falls outside it reports as unaccounted — trading a correctness property
for latency.
