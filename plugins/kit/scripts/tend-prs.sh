#!/usr/bin/env bash
# Run one /kit:tend-prs pass headlessly, with nobody at the keyboard.
#
# Invoked by the launchd agent that install-tending.sh writes, or by hand to
# test the exact thing the schedule runs. Every pass is cold: it derives all
# state from GitHub and git, so a killed firing costs nothing and the next one
# picks up where evidence says to.
#
# Usage: tend-prs.sh [options]
#
#   --repo-dir <path>   main checkout to tend; default: cwd
#   --model <id>        model to run the pass on
#   --timeout <secs>    kill the pass after this long (default 1800)
#   --dry-run           print the invocation and exit without running it
#
# The permission grant lives in tending-settings.json next to this file — that
# is the safety boundary, not this script. Nothing here can be approved
# interactively, so a tool outside the allowlist fails the pass and gets
# reported. That is the intended behavior, not a limitation to work around:
# widening the boundary is an edit to a file you can read and diff.
#
# Everything is detected at runtime. There is no config file to write.

set -uo pipefail

# Sonnet, not Opus, and matching what tend-prs.md declares in its own frontmatter
# — a script that hardcodes a different model silently overrides the command's
# choice. The pass reads `gh` JSON, matches branches to worktrees, and runs
# `lsof`; the one judgment-heavy step, verifying review findings against the
# code, is /kit:review-copilot, which declares sonnet too. This is not
# pr-review.sh, where the model is the deliverable.
#
# Goes stale; override with --model rather than editing callers.
MODEL="claude-sonnet-5"
REPO_DIR=""
TIMEOUT=1800
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    --model)    MODEL="$2"; shift 2 ;;
    --timeout)  TIMEOUT="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)  sed -n '2,22p' "$0"; exit 0 ;;
    *)          echo "error: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${SCRIPT_DIR}/tending-settings.json"
[ -f "$SETTINGS" ] || { echo "error: no permission grant at ${SETTINGS}" >&2; exit 1; }

[ -n "$REPO_DIR" ] || REPO_DIR="$(pwd)"
cd "$REPO_DIR" 2>/dev/null || { echo "error: cannot cd to ${REPO_DIR}" >&2; exit 1; }

# Tend from the main checkout, never a linked worktree. The pass removes
# worktrees whose PRs merged, and a pass running inside its own target would be
# deleting the ground it stands on. --git-common-dir resolves to the main
# checkout's .git from anywhere, which is why it is used instead of --show-toplevel.
#
# It is absolutized by cd rather than --path-format=absolute: that flag arrived
# in git 2.31, and older git does not fail on it — it echoes the unknown flag
# back and returns a relative `.git`, so dirname silently yields the wrong
# directory. The cd works on every version.
COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null)"
[ -n "$COMMON_DIR" ] || { echo "error: ${REPO_DIR} is not a git repository" >&2; exit 1; }
MAIN_CHECKOUT="$(cd "$COMMON_DIR/.." 2>/dev/null && pwd)"
[ -n "$MAIN_CHECKOUT" ] || { echo "error: could not resolve main checkout from ${REPO_DIR}" >&2; exit 1; }
cd "$MAIN_CHECKOUT" || exit 1

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
[ -n "$REPO" ] || { echo "error: could not resolve repo from ${MAIN_CHECKOUT}" >&2; exit 1; }

# --- Log ----------------------------------------------------------------------
# Nothing is attached to this process, so the log is the only record a pass
# leaves behind. One file per repo, appended: the interesting question after the
# fact is "what has this been skipping for three days", and that reads badly
# across a directory of timestamped files.
LOGDIR="$HOME/.claude/logs/tend-prs"
mkdir -p "$LOGDIR"
LOG="${LOGDIR}/$(printf '%s' "$REPO" | tr '/' '-').log"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$LOG"; }

# --- Mutual exclusion ---------------------------------------------------------
# Derived state makes an overlapping firing harmless in principle, with one
# exception that matters: two passes triaging the same PR at once is a double
# push of the same fixes. macOS has no flock(1), so the lock is an atomic mkdir
# holding the pid — the one filesystem primitive that cannot race.
LOCK="${LOGDIR}/$(printf '%s' "$REPO" | tr '/' '-').lock"

if ! mkdir "$LOCK" 2>/dev/null; then
  HOLDER="$(cat "${LOCK}/pid" 2>/dev/null || true)"
  # A pass killed mid-flight leaves the directory behind. Reclaim it only when
  # the recorded pid is provably gone — a live holder is exactly what the lock
  # is for, and stealing from one is the double-push this prevents.
  if [ -n "$HOLDER" ] && kill -0 "$HOLDER" 2>/dev/null; then
    log "skipped: pass already running (pid ${HOLDER})"
    exit 0
  fi
  log "reclaiming stale lock (pid ${HOLDER:-unknown} is gone)"
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null || { log "skipped: could not take lock"; exit 0; }
fi
printf '%s' "$$" >"${LOCK}/pid"
trap 'rm -rf "$LOCK"' EXIT INT TERM

# --- Force subscription auth --------------------------------------------------
# launchd hands this process whatever environment it was loaded with. If
# ANTHROPIC_API_KEY is set, the headless `claude -p` below silently bills to the
# API account instead of the subscription. Same rule as pr-review.sh.
AUTH_NOTE=""
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  AUTH_NOTE=" (ANTHROPIC_API_KEY was set and unset)"
  unset ANTHROPIC_API_KEY
fi
unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL

CLAUDE_BIN="$(command -v claude || true)"
[ -n "$CLAUDE_BIN" ] || CLAUDE_BIN="$HOME/.local/bin/claude"
[ -x "$CLAUDE_BIN" ] || { log "failed: no claude binary at ${CLAUDE_BIN}"; exit 1; }

# --- Prompt -------------------------------------------------------------------
# The pass itself is /kit:tend-prs. This says only what the command cannot know
# about its own invocation: that there is genuinely no terminal, and what to do
# when it runs into something it is not permitted to do.
PROMPT="Run one complete /kit:tend-prs pass over ${REPO}, from the main checkout at ${MAIN_CHECKOUT}. Invoke it via the Skill tool and follow it as written.

You are running headlessly from a scheduled launchd job. There is no terminal attached and no one to prompt — the command's no-questions constraint is a fact of this environment, not an instruction you could choose to disregard.

Your permissions are a fixed allowlist. If you need a tool or command outside it, the call fails: do not retry it, do not look for another way around it, and do not treat the denial as a reason to skip silently. Record what was denied and why you wanted it, then carry on with the rest of the pass — a permission boundary that turns out to be too narrow is something to widen deliberately, after reading the report.

Finish by printing the command's Step 7 report, in full, including every skip reason. It is written to a log nobody is watching in real time, so the report is the whole record of this pass."

if [ "$DRY_RUN" = "1" ]; then
  echo "repo:     ${REPO}"
  echo "checkout: ${MAIN_CHECKOUT}"
  echo "settings: ${SETTINGS}"
  echo "log:      ${LOG}"
  echo "would run: ${CLAUDE_BIN} -p --model ${MODEL} --settings ${SETTINGS} <prompt>"
  exit 0
fi

# --- Run ----------------------------------------------------------------------
log "=== pass start repo=${REPO} checkout=${MAIN_CHECKOUT} model=${MODEL} auth=subscription${AUTH_NOTE}"

# A hung pass must not hold the lock until the next reboot. `timeout` is not on
# a stock macOS, so the watchdog is a background sleep that kills this process
# group — cheap, and it fires whether the hang is in the model or in a gh call.
( sleep "$TIMEOUT"; kill -TERM -$$ 2>/dev/null ) &
WATCHDOG=$!

"$CLAUDE_BIN" -p \
  --model "$MODEL" \
  --settings "$SETTINGS" \
  "$PROMPT" >>"$LOG" 2>&1 </dev/null
STATUS=$?

kill "$WATCHDOG" 2>/dev/null

if [ "$STATUS" -eq 0 ]; then
  log "=== pass end ok"
else
  log "=== pass end FAILED (exit ${STATUS})"
  # Escalate the same way the command does. A pass that cannot run at all is
  # exactly the case the quiet-pass rule is not meant to cover.
  osascript -e "display notification \"tend-prs pass failed (exit ${STATUS}) — see ${LOG}\" with title \"Claude Code\" subtitle \"${REPO}\" sound name \"Glass\"" 2>/dev/null
fi

exit "$STATUS"
