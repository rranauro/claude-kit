# The reviewer script

`plugins/kit/scripts/pr-review.sh` holds the review prompt, and three entry
points share it: the [`pr-review-on-create` hook](hooks.md), `/kit:start-review`,
and a manual re-run after you push fixes. Keeping one copy is what makes a second
pass comparable to the first.

It decides delivery by authorship. Your own PR gets the review posted as a
comment; a colleague's gets a file under `<main-checkout>/reviews/pr-<n>/`, and
posting to it requires an explicit `--post`. An unresolved login falls to the
file side — the failure mode should be a review you have to go read, not an
uninvited comment on someone else's work. Scope narrows the same way: full
categories on your own PRs, bugs and security only on everyone else's.

Everything is detected at runtime — repo via `gh`, your login via `gh api user`,
the main checkout via `git rev-parse --git-common-dir` so artifacts survive the
worktree they were produced in. There is no config file to write. Run it by hand
with `pr-review.sh --help`.
