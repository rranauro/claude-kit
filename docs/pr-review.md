# The reviewer script

`plugins/kit/scripts/pr-review.sh` holds the review prompt, and three entry
points share it: the [`pr-review-on-create` hook](hooks.md), `/kit:start-review`,
and a manual re-run after you push fixes. Keeping one copy is what makes a second
pass comparable to the first.

A PR gets Copilot's review always, and a second, independent Claude review
wherever a project has registered the hook — see
[ADR 0004](adr/0004-restore-the-pr-review-hook.md).

It decides delivery by authorship. Your own PR gets the review posted as a
comment; a colleague's gets a file, and posting to it requires an explicit
`--post`. An unresolved login falls to the
file side — the failure mode should be a review you have to go read, not an
uninvited comment on someone else's work. Scope narrows the same way: full
categories on your own PRs, bugs and security only on everyone else's.

Everything is detected at runtime — repo via `gh`, your login via `gh api user`,
the main checkout via `git rev-parse --git-common-dir` so artifacts survive the
worktree they were produced in. There is no config file to write. Run it by hand
with `pr-review.sh --help`.

The file lands in the main checkout, under the project the PR changes — found
from the PR's own file list, not the local diff, because `/kit:start-review`
runs it from the main checkout where that diff is empty. A project that declares
a `Location:` under `## Visual PR and review output`, in the files and order
`kit:project-rules` gives, gets it there, beside what
`kit:visual-pr` and `kit:visual-review` write; otherwise it goes to
`tmp/reviews/pr-<n>/` where that is gitignored, and inside `.git` where it is
not, so a review never shows up as untracked work. The script prints the path,
which is the only copy of it a caller should read.
