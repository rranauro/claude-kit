# The kit is versioned by its commit, not by a number in plugin.json

`claude plugin update` only notices a change when the plugin's version moves. A
`version` in `plugin.json` that nobody raised kept installed sessions on the old
payload for 56 commits (#152), so every PR under `plugins/kit/` was made to bump
it, and a required check enforced the bump.

That put one line in every plugin PR. Two passes in flight at once both raised
it to the same next number, so the second conflicted every time, and a pass may
not resolve a conflict by bringing `main` into its branch. Running more of the
workflow unattended and in parallel turned an occasional collision into the
normal case.

We decided to drop the field. With no `version` in `plugin.json` or in the
marketplace entry, users "track your commits instead" (Claude Code docs, *Host
and maintain a marketplace*, "Release a new version"). That covers a
relative-path entry in a git-hosted marketplace, which is how this one is laid
out, so every merge to `main` is an update and nobody edits anything for it to
be one. `scripts/lint.sh` fails if a `version` comes back, because that
is the one way the #152 freeze returns. When a release needs a readable name,
it gets a git tag.

## Considered Options

**A bot that bumps the version after merge.** This keeps a readable number
without a shared line in every PR, and it is the option most likely to be
proposed again. It was rejected because it needs either a bypass of the "Require
PR" ruleset, so the bot can push to `main`, or a bump PR of its own after every
merge. Either is more machinery for the same result the commit already gives,
and the bypass weakens the one rule that keeps `main` reviewed.

**Keep per-PR bumps and run passes one at a time.** Serialising passes removes
the conflict. It was rejected because the runner exists to work several tickets
at once (`docs/shipping-on-a-runner.md`), and this gives that up to protect a
number nothing in the kit reads.

**Declare the version only in the marketplace entry.** That moves the shared
line instead of removing it, so every plugin PR would still edit it. Declaring a
version in both places is the documented trap, because `plugin.json` wins
silently.

## Consequences

`claude plugin list` shows a 12-character SHA where a number used to be. A tag
is how a human names a release, and tagging is by hand.

The docs do not say whether the SHA is the repository's HEAD or the last commit
that touched `plugins/kit/`. If it is HEAD, a docs-only merge makes installed
clients reinstall an unchanged payload. That is harmless, and it is the price of
never missing a real change.
