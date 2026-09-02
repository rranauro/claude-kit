# Editing the kit while a session is open

Half of what this plugin ships is read once, when the session starts. The other
half is read every time it runs. Editing across that line is the difference
between a change that takes effect and one that will not until you restart, and
nothing in the checkout looks different either way.

| Payload | When it is read | An edit takes effect |
|---|---|---|
| `plugins/kit/commands/*.md` | Session start | After a restart |
| `plugins/kit/skills/*/SKILL.md` and its bundled files | Session start | After a restart |
| `plugins/kit/scripts/*.sh` | Every run, by path | Immediately |
| `plugins/kit/hooks/rails-quality-gates.sh` | Every fire, by path | Immediately |

The scripts and the hook are on the immediate side because nothing loads their
contents — a command names one by path, `${CLAUDE_PLUGIN_ROOT}/scripts/pr-review.sh`,
and the shell executes the file on disk. The prose deciding *whether* to run it
was fixed at session start; the script it runs is whatever you last saved.

## A command edited here keeps running until you restart

This checkout resolves the plugin from its own tree, so the file you edit is the
file the plugin ships. That is what makes the stale version hard to see: the
path is right, the content is right, `git log` is right, and the behavior is the
one from before you started.

It bites hardest in this repo, because `CLAUDE.md` requires the workflow to be
changed through the workflow. You ship a change to `/kit:ship-ticket`, invoke it
to watch the change work, and get the version from session start. Merging the PR
does not help. Pulling does not help. **Restart the session** — that is the only
thing that picks a command or skill body up.

## A skill body you are quoting may be a snapshot

The loud half of this is a command that behaves wrong, and you at least see
something. The quiet half is worse: an injected skill body reads exactly like
the file, with no marker saying which it is. A fact read out of one mid-session
can be stale while reading as authoritative — a step that has since been
rewritten, a command it names that has since been deleted — and nothing about
the reading feels uncertain. What comes out of that is a bug filed against a
file that is already correct.

So the question before quoting a command or skill as evidence is not *have I
read this?* but **am I reading the file, or a snapshot?** Where the answer
matters — filing a bug against a prompt file, asserting what a command does now,
checking whether an edit landed — read the file with `cat` and quote that. A
targeted read costs nothing, and it is the only thing that tells the two apart.

"Restart to be safe" is the wrong lesson, and the reason the table is here:
most of what you touch on a given day sits on one side of the line or the other,
and knowing which is cheaper than restarting on every edit.
