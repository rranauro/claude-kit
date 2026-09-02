# The reviewer script

`plugins/kit/scripts/pr-review.sh` holds the review prompt, and two entry points
share it: `/kit:start-review`, and a manual re-run after you push fixes. Keeping
one copy is what makes a second pass comparable to the first.

Nothing fires it on its own. Copilot is the only automated reviewer a PR gets —
see [ADR 0003](adr/0003-one-automated-reviewer.md) — so this script runs when you
ask for it.

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
