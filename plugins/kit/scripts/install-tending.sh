#!/usr/bin/env bash
# Install (or remove) the launchd agent that runs tend-prs.sh on a schedule.
#
# Usage: install-tending.sh [options]
#
#   --repo-dir <path>    main checkout to tend; default: cwd
#   --interval <mins>    minutes between passes (default 10)
#   --model <id>         model to pass through to tend-prs.sh
#   --uninstall          unload and remove the agent for this repo
#   --status             show whether the agent is loaded, and the last pass
#
# One agent per repo, labelled by the repo it tends, so tending two checkouts is
# two installs and removing one leaves the other alone.
#
# launchd rather than cron: it survives logout, restarts the job if the machine
# was asleep at the scheduled time, and is the supported mechanism on macOS.
# Cloud scheduling cannot work here at all — the pass needs the real worktrees
# and the local gh and claude credentials.

set -uo pipefail

REPO_DIR=""
INTERVAL=10
MODEL=""
ACTION="install"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-dir)  REPO_DIR="$2"; shift 2 ;;
    --interval)  INTERVAL="$2"; shift 2 ;;
    --model)     MODEL="$2"; shift 2 ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --status)    ACTION="status"; shift ;;
    -h|--help)   sed -n '2,19p' "$0"; exit 0 ;;
    *)           echo "error: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/tend-prs.sh"
[ -x "$RUNNER" ] || { echo "error: ${RUNNER} is not executable" >&2; exit 1; }

[ -n "$REPO_DIR" ] || REPO_DIR="$(pwd)"
# Absolutized by cd, not --path-format=absolute — see the note in tend-prs.sh:
# git before 2.31 returns a relative path and no error for that flag.
MAIN_CHECKOUT="$(cd "$REPO_DIR" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." 2>/dev/null && pwd)"
[ -n "$MAIN_CHECKOUT" ] || { echo "error: ${REPO_DIR} is not a git repository" >&2; exit 1; }

REPO="$(cd "$MAIN_CHECKOUT" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
[ -n "$REPO" ] || { echo "error: could not resolve the GitHub repo for ${MAIN_CHECKOUT}" >&2; exit 1; }

SLUG="$(printf '%s' "$REPO" | tr '/' '-')"
LABEL="net.claude-kit.tend-prs.${SLUG}"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG="${HOME}/.claude/logs/tend-prs/${SLUG}.log"

# --- status -------------------------------------------------------------------
if [ "$ACTION" = "status" ]; then
  echo "repo:     ${REPO}"
  echo "checkout: ${MAIN_CHECKOUT}"
  echo "label:    ${LABEL}"
  if [ -f "$PLIST" ]; then
    echo "plist:    ${PLIST}"
  else
    echo "plist:    (not installed)"
  fi
  if launchctl list 2>/dev/null | grep -qF "$LABEL"; then
    echo "loaded:   yes"
  else
    echo "loaded:   no"
  fi
  if [ -f "$LOG" ]; then
    echo "log:      ${LOG}"
    # Passes are bounded by their own start/end markers, so the last one can be
    # cut exactly rather than guessed at with a line count — a quiet pass is two
    # lines and a busy one is fifty, and `tail -20` truncates the report you
    # actually wanted to read.
    echo
    echo "--- last pass ---"
    awk '/=== pass start/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG"
    echo "--- to follow the next one: tail -f ${LOG}"
  else
    echo "log:      (no pass has run yet — it runs by hand too:"
    echo "          ${RUNNER} --repo-dir ${MAIN_CHECKOUT})"
  fi
  exit 0
fi

# --- uninstall ----------------------------------------------------------------
# Unload before removing the file. A plist deleted while still loaded leaves
# launchd running a job with nothing on disk to describe it, and the only way
# back is to remember the label you no longer have written down anywhere.
if [ "$ACTION" = "uninstall" ]; then
  launchctl unload "$PLIST" 2>/dev/null
  launchctl remove "$LABEL" 2>/dev/null
  if [ -f "$PLIST" ]; then
    rm -f "$PLIST"
    echo "removed ${PLIST}"
  else
    echo "nothing installed for ${REPO}"
  fi
  echo "the log at ${LOG} is left in place — remove it by hand if you want it gone"
  exit 0
fi

# --- install ------------------------------------------------------------------
case "$INTERVAL" in
  ''|*[!0-9]*) echo "error: --interval must be a whole number of minutes" >&2; exit 1 ;;
esac
[ "$INTERVAL" -ge 1 ] || { echo "error: --interval must be at least 1" >&2; exit 1; }

MODEL_ARGS=""
[ -n "$MODEL" ] && MODEL_ARGS="        <string>--model</string>
        <string>${MODEL}</string>"

mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/.claude/logs/tend-prs"

# PATH is set explicitly because launchd agents do not inherit a login shell's
# environment: gh, claude, and git all live in places a bare launchd PATH does
# not include, and the failure without this is a job that runs on schedule and
# reports "command not found" forever.
cat >"$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${RUNNER}</string>
        <string>--repo-dir</string>
        <string>${MAIN_CHECKOUT}</string>
${MODEL_ARGS}
    </array>
    <key>WorkingDirectory</key>
    <string>${MAIN_CHECKOUT}</string>
    <key>StartInterval</key>
    <integer>$((INTERVAL * 60))</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${HOME}/.claude/logs/tend-prs/${SLUG}.launchd.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.claude/logs/tend-prs/${SLUG}.launchd.log</string>
</dict>
</plist>
PLIST_EOF

# Reload rather than load, so re-running this with a new interval replaces the
# agent instead of erroring on a label that is already there.
launchctl unload "$PLIST" 2>/dev/null
launchctl load "$PLIST" 2>/dev/null || { echo "error: launchctl load failed for ${PLIST}" >&2; exit 1; }

echo "installed ${LABEL}"
echo "  repo:     ${REPO}"
echo "  checkout: ${MAIN_CHECKOUT}"
echo "  interval: every ${INTERVAL} minutes"
echo "  log:      ${LOG}"
echo
echo "Passes begin at the next interval. To watch one now, run the pass by hand:"
echo "  ${RUNNER} --repo-dir ${MAIN_CHECKOUT}"
echo "To check on it later: ${SCRIPT_DIR}/install-tending.sh --status --repo-dir ${MAIN_CHECKOUT}"
