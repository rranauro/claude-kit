# Hooks

`plugins/kit/hooks/rails-quality-gates.sh` is the one hook the kit ships — a
`PreToolUse` hook that holds `git commit` to RuboCop and Brakeman on the staged
Ruby files, blocking the commit with the tool output so Claude fixes it and
retries. No-ops unless the `Gemfile` carries both. Kill switch: `export
SKIP_RAILS_GATES=1`.

Register it in a **project's** `.claude/settings.json` rather than the global
one, so it fires only for the repos you want it in.

## Registering it

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /ABSOLUTE/PATH/TO/claude-kit/plugins/kit/hooks/rails-quality-gates.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

Use an absolute path. `${CLAUDE_PLUGIN_ROOT}` only resolves for hooks a plugin
registers itself, not for ones you wire up in your own settings. Where the script
sits depends on how the kit reached you: a marketplace install puts it under
`~/.claude/plugins/marketplaces/claude-kit/plugins/kit/hooks/`, while the
claude-kit checkout resolves the plugin from its own tree, so there it is
`plugins/kit/hooks/` under the checkout root.

The `timeout` is worth keeping: Brakeman scans the whole app and the default is
not generous enough for a large one. The script filters its own trigger — it acts
only on `git commit` — so the broad `Bash` matcher costs a fast no-op on every
other command.

## Why it isn't auto-registered

A plugin can ship a `hooks/hooks.json` that turns its hooks on for every repo the
plugin is enabled in. This one should not work that way: it blocks your commits.
Opting in per project is the point.

## Why the Rails opinion is a hook and not a command

A gate is binary — did it pass? — and a hook can't be talked out of it the way a
command can when the code looks fine. Remediation is the opposite: triaging a
Brakeman finding into a real XSS or a false positive is judgment, and a shell
script has none. So the hook enforces and `/kit:commit` fixes, which keeps
`/kit:commit` stack-neutral and lets non-Rails users simply not register the hook.
Tests stay in the command for the same reason — choosing which tests cover a
change is judgment, and a full suite would blow the hook timeout.
