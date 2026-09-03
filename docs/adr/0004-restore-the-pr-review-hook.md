# Restore the pr-review-on-create hook

ADR 0003 removed a `PostToolUse` hook that fired a headless Claude review at
`gh pr create` time, bundled with the whole laptop-tending loop it shipped
alongside. Its own considered options weighed keeping the hook alone and
rejected it: coverage was "conditional on who opened the PR and how — a PR
opened from the web, from a runner, or from a session without the hook
registered gets one reviewer anyway."

That premise assumed a PR could arrive by any of those paths. It doesn't, in
practice: every PR this kit produces is opened by `/kit:new-pull-request`,
from inside a Claude Code session — interactive or a headless `claude -p`
runner — never from the web, never from a bare `git push`. Coverage isn't
conditional; it's certain wherever a project registers the hook. The premise
that sank the option no longer holds, so the option is worth taking.

The scheduling loop the hook was bundled with — polling for PRs, its
installer, its own permission grant — stays gone; the hook was always the
narrower, self-contained piece, and restoring it does not restore what it was
removed with.

## Considered Options

**Leave it removed, keep Copilot as the only automated reviewer.** The status
quo since ADR 0003. Rejected because a second, independent review before a
human looks is worth having when it costs nothing to keep reliable, and the
reason it was unreliable no longer applies.

**Move the Claude review into CI**, the alternative ADR 0003 left open.
Considered and set aside for now, not ruled out: it is a change to each
consuming project's own workflow rather than to this plugin, and it needs its
own cost-per-PR decision, separate from restoring a hook that already existed
and already worked.

## Consequences

A PR opened from a Claude Code session gets two independent reviews before a
human looks, wherever the project has registered the hook — see
[tending on a CI runner](../tending-on-a-runner.md#two-automated-reviewers-wherever-the-hook-is-registered)
for what each reviewer posts and how `/kit:review-copilot` reads both.

Registration stays opt-in per project, unchanged from before: nothing fires
anywhere until a project's own `.claude/settings.json` registers the hook.
