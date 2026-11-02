# How the freeze is enforced — facts (issue #362)

The question: in `kit:ticket-loop` Phase 2 `tdd`
(`plugins/kit/skills/ticket-loop/SKILL.md:138`), an isolated writer subagent
commits failing tests; the main session (implementer) must make them pass
without editing those files. Can that be enforced mechanically, or only by
instruction plus a hand-off diff check? Facts only; no design chosen here.

Checked against Claude Code 2.1.316 docs (code.claude.com, 2026-11-02) and one
local experiment.

## 1. Plugins can register hooks; the kit doesn't today

- A plugin registers hooks in `hooks/hooks.json` at the plugin root, or through
  a `hooks` key in `.claude-plugin/plugin.json` (path, inline object, or array;
  merged with `hooks/hooks.json`). "When a plugin is enabled, its hooks merge
  with your user and project hooks." `${CLAUDE_PLUGIN_ROOT}`,
  `${CLAUDE_PLUGIN_DATA}` and `CLAUDE_PROJECT_DIR` are exported to hook commands.
  - https://code.claude.com/docs/en/plugins-reference#hooks
  - https://code.claude.com/docs/en/plugins-reference#environment-variables
  - https://code.claude.com/docs/en/hooks#hook-locations
- The kit ships two hook scripts but registers neither: no
  `plugins/kit/hooks/hooks.json`, no `hooks` key in
  `plugins/kit/.claude-plugin/plugin.json`. `docs/hooks.md:3-5` says to register
  them per project in `.claude/settings.json` "so each fires only for the repos
  you want it in"; `plugins/kit/hooks/pr-review-on-create.sh:11-12` and
  `rails-quality-gates.sh:14-16` repeat it. A plugin-registered hook would be
  the kit's first auto-on hook, firing in every project with the plugin
  enabled — a departure from that stated choice (it could self-gate, e.g. no-op
  unless a freeze list exists).

## 2. PreToolUse can tell main from subagent, and can block

- **Identity.** Common input fields: `session_id`, `transcript_path`, `cwd`,
  `permission_mode`, `hook_event_name`, plus `agent_id` / `agent_type` "which
  agent a hook fired in, such as a subagent". Docs don't say outright that they
  are absent in the main session.
  https://code.claude.com/docs/en/hooks#common-input-fields
- **Verified locally** (2.1.316, `claude -p`, PreToolUse hook logging stdin,
  main session ran a Bash call then spawned a general-purpose subagent that ran
  one):
  - main call: `agent_id` and `agent_type` **absent**
  - subagent call: `agent_id: "a9577ef71571693d1"`, `agent_type: "general-purpose"`
  - `session_id`, `transcript_path`, `cwd` **identical** in both, so they don't
    discriminate. Caveat: under `claude --agent <name>` the main session also
    carries `agent_type`; `agent_id` is the field to test.
- **Blocking.** Exit 2 (stderr fed to Claude) or JSON
  `hookSpecificOutput.permissionDecision: "deny"` blocks the call; exit 2 wins
  even over an allow rule. A timed-out hook does **not** block unless
  `"onFailure": "block"`. https://code.claude.com/docs/en/hooks#pretooluse,
  https://code.claude.com/docs/en/permissions#extend-permissions-with-hooks
- **Tool inputs.** `Write`/`Edit` carry absolute `tool_input.file_path`;
  `NotebookEdit` carries `notebook_path`; `Bash` carries only
  `tool_input.command` (a string). So file tools can be matched on path
  exactly; Bash only by parsing command text.
- **Bash is the hole.** Permissions docs: a Bash rule "isn't a security boundary
  around the program" (`sh -c`, absolute paths, alternate spellings slip past).
  Built-in Edit deny rules do cover `sed`, `tee`, and redirect targets, but "not
  ... arbitrary subprocesses that read or write files indirectly, like a Python
  or Node script". A custom hook parsing `command` has the same limits, plus
  `git checkout <sha> -- f`, `git apply`, `mv`, `cp`, `ruby -e`, etc. Only the
  sandbox gives OS-level write denial for Bash and children.
  https://code.claude.com/docs/en/permissions#what-a-bash-rule-doesnt-match,
  https://code.claude.com/docs/en/permissions#what-read-and-edit-rules-cover
- **Static alternatives are session-wide.** `Edit(path)` deny rules and sandbox
  write restrictions live in settings, apply to main and subagents alike, and
  aren't per-ticket. (`Write(path)`/`NotebookEdit(path)` rules never match; use
  `Edit(path)`.) A hook re-reads its inputs on every call, so it is the only
  mechanism here that can pick up a per-ticket list mid-session.
  https://code.claude.com/docs/en/permissions#writepath-notebookeditpath-and-globpath-rules-never-match
- **Getting the frozen list to the hook.** Nothing built in; the hook reads
  whatever file it is told about. It gets `cwd` (the worktree root once in a
  worktree; `CLAUDE_PROJECT_DIR` stays at the original root —
  https://code.claude.com/docs/en/hooks#environment-variables), so it can run
  `git -C "$cwd" rev-parse --git-dir` and read a list in the per-worktree git
  dir (untracked, outside the tree), or in `${CLAUDE_PLUGIN_DATA}`. Note
  sequencing: the writer has returned before the implementer edits, so a list
  written at writer hand-off blocks everyone after it — the agent_id check
  matters only if a subagent must still edit those files later (e.g. a
  re-write round).
- `SubagentStop` input carries `agent_id`, `agent_type`,
  `agent_transcript_path`, `last_assistant_message` — a possible place to
  record the list/sha when the writer finishes.

## 3. Writer-side scoping via agent frontmatter: mostly not for a plugin agent

- Subagent frontmatter supports `hooks` (active "only while that specific
  subagent is active"), `tools`, `disallowedTools`, `permissionMode`,
  `isolation: worktree`, `model`.
  https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields
- But: "plugin subagents don't support the `hooks`, `mcpServers`, or
  `permissionMode` frontmatter fields. These fields are ignored when loading
  agents from a plugin." Docs point plugin authors to `hooks/hooks.json`
  instead. So a writer shipped like `plugins/kit/agents/shape-reviewer.md`
  can't carry its own hooks.
- `tools` / `disallowedTools` do work for plugin agents but are whole-tool, not
  path-scoped: "A `disallowedTools` entry with a specifier ... still removes the
  whole tool". The writer could be denied, say, Bash, but not limited to
  `spec/**` by frontmatter.
- Frontmatter scoping restrains the writer anyway, not the implementer; the
  freeze binds the main session, which has no frontmatter. The plugin hook with
  an `agent_id` test (section 2) is the mechanical route that targets the
  implementer.

## 4. Fallback: instruction + hand-off diff check

`git diff --exit-code <writer-sha> -- <frozen paths>` compares the writer's
commit to the working tree, so it catches edits however they were made (any
tool, any Bash form), which the hook can't. Gaps:

- **Where the sha comes from.** If the implementer can rewrite it, the check
  is void. Recorded from the writer's return message (or a SubagentStop hook)
  by the orchestrating step, it survives an amend/rebase: the old sha stays in
  the object store (reflog keeps it ~90 days by default; unreachable objects are
  pruned after `gc.pruneExpire`, 2 weeks), and the diff against the working tree
  still shows the change. `git merge-base --is-ancestor <writer-sha> HEAD`
  additionally detects that history was rewritten.
- **Renames/deletes.** Diff by listed paths shows a deleted or moved frozen
  file as a deletion; fine if the list is explicit, missed if it's a glob
  computed at hand-off time.
- **Neutering without touching the files.** The diff doesn't see a test
  disabled from elsewhere: `spec_helper`/`rails_helper` `filter_run_excluding`,
  `.rspec` options, a CI or runner config skipping the path, a stubbed helper the
  tests call, a factory change. Running the frozen tests by path at hand-off
  and confirming they ran and passed (not 0 examples) closes most of this; it's
  a separate check from the diff.
- **Timing.** Hand-off finds the edit after the work; the implementer's time is
  already spent, and the remedy (revert those files, re-run) is the check's
  job to state.

## What the facts allow

- **Mechanical, file tools:** a plugin `hooks/hooks.json` PreToolUse hook on
  `Edit|Write|NotebookEdit` (and `MultiEdit` where present) that denies listed
  paths when `agent_id` is absent. Exact and reliable for those tools.
- **Mechanical, Bash:** best-effort only (parse `command`); not a boundary.
  The sandbox is the only OS-level option and is static, session-wide config.
- **Writer-scoped frontmatter hooks:** unavailable for a plugin-shipped agent.
- **Instruction + hand-off diff (+ running the frozen tests):** catches every
  write path after the fact, provided the writer sha is held outside the
  implementer's reach.
- The hook and the diff aren't exclusive: one blocks the common path early, the
  other is the backstop for Bash and indirect writes.
