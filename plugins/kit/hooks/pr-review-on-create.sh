#!/usr/bin/env bash
# PostToolUse hook: when `gh pr create` succeeds in a Claude Code Bash call,
# fire a headless review of the new PR and post it as a GitHub PR comment.
# Non-blocking; exits 0 immediately.
#
# Detects and delegates only — the prompt, auth handling, delivery rules, and
# provenance footer live in scripts/pr-review.sh, so this hook, /kit:start-review,
# and manual re-runs all produce the same review.
#
# Registered by hooks/hooks.json, so it ships and versions with the reviewer it
# delegates to. That means it fires in every repo you create a PR from — the
# posting rule in pr-review.sh is what keeps it off other people's work: it posts
# only when the PR author is you, and writes to a file otherwise.
# Kill switch: export SKIP_PR_REVIEW=1.

set -u

[[ -n "${SKIP_PR_REVIEW:-}" ]] && exit 0

# Resolved relative to this file, so it works from the marketplace cache or a
# local clone. ${CLAUDE_PLUGIN_ROOT} is not set for hooks you register yourself.
REVIEWER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/pr-review.sh"
[ -x "$REVIEWER" ] || exit 0

INPUT=$(cat)

RESULT=$(INPUT="$INPUT" python3 - 2>/dev/null <<'PY'
import json, os, re, sys
try:
    d = json.loads(os.environ.get("INPUT") or "{}")
except ValueError:
    sys.exit(0)
if d.get("tool_name") != "Bash":
    sys.exit(0)
cmd = (d.get("tool_input") or {}).get("command", "") or ""
if not re.search(r"\bgh\s+pr\s+create\b", cmd):
    sys.exit(0)
resp = d.get("tool_response") or {}
out = (resp.get("stdout") or "") + (resp.get("stderr") or "")
if isinstance(resp, str):
    out += resp
m = re.search(r"https://github\.com/[^/\s]+/[^/\s]+/pull/\d+", out)
if not m:
    sys.exit(0)
print(m.group(0))
print(d.get("cwd") or "")
PY
)

PR_URL=$(printf '%s\n' "$RESULT" | sed -n '1p')
CWD=$(printf '%s\n' "$RESULT" | sed -n '2p')

[ -n "$PR_URL" ] || exit 0
[ -n "$CWD" ] || CWD=$(pwd)

(
  cd "$CWD" 2>/dev/null || true
  "$REVIEWER" --detach --source "pr-review-on-create hook" "$PR_URL" >/dev/null 2>&1
) &

exit 0
