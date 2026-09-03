#!/usr/bin/env bash
# Ship every startable ticket under a label, one process each — the runner
# ship-ticket.md names as "#101": a fresh `claude -p` per ticket, so no ticket
# ever runs in a context that carried a previous one. See
# docs/shipping-on-a-runner.md for the gotchas this works around.
#
#   ship-startable.sh <label> [--repo DIR] [--max N] [--poll-seconds N]
#                     [--project-settings FILE] [--model NAME]
#
# --max caps tickets shipped in one run (default 20) — the safety valve if the
# startable check is ever wrong; the run stops and says so rather than opening
# PRs without bound.
# --poll-seconds is how often the run re-checks after finding nothing
# startable while a PR it opened is still open (default 120) — short enough to
# notice a blocker closing well inside the ~15-minute round trip #101's own
# text observed. Not meant to be tuned; the flag exists for the rare case a
# consuming project's CI is unusually slow or fast.
# --project-settings merges a project's own test/lint permission grant over
# ship-settings.json, the same split scripts/tending-settings.json uses.
#
# Run it directly in a terminal and leave — nothing here schedules itself, no
# cron, no cloud runner. A crashed or killed per-ticket call needs no cleanup
# of its own: whatever worktree it left behind is exactly what the next
# `/kit:ship-ticket` call's own Step 0 reclaim sweep picks up. Ctrl-C, a
# signal, or hitting --max all end the run the same way: a summary naming
# what shipped, what parked, and what (if anything) was still open.
set -uo pipefail

LABEL=""
REPO="$PWD"
MAX=20
POLL_SECONDS=120
PROJECT_SETTINGS=""
MODEL="${SHIP_STARTABLE_MODEL:-claude-opus-5}"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)             REPO="$2"; shift 2 ;;
    --max)               MAX="$2"; shift 2 ;;
    --poll-seconds)      POLL_SECONDS="$2"; shift 2 ;;
    --project-settings)  PROJECT_SETTINGS="$2"; shift 2 ;;
    --model)             MODEL="$2"; shift 2 ;;
    -*) echo "ship-startable: unknown option: $1" >&2; exit 2 ;;
    *)
      if [ -n "$LABEL" ]; then
        echo "ship-startable: unexpected argument: $1 (label already given: $LABEL)" >&2
        exit 2
      fi
      LABEL="$1"; shift ;;
  esac
done

[ -n "$LABEL" ] || {
  echo "usage: ship-startable.sh <label> [--repo DIR] [--max N] [--poll-seconds N] [--project-settings FILE] [--model NAME]" >&2
  exit 2
}

cd "$REPO" 2>/dev/null || { echo "ship-startable: no such directory: $REPO" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "ship-startable: not a git repository: $REPO" >&2; exit 2; }
REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"

CLAUDE_BIN="$(command -v claude || true)"
[ -n "$CLAUDE_BIN" ] || CLAUDE_BIN="$HOME/.local/bin/claude"
[ -x "$CLAUDE_BIN" ] || { echo "ship-startable: claude CLI not found" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "ship-startable: gh CLI not found" >&2; exit 2; }

# --- settings: kit's grant, plus a project's own test/lint commands --------
# The default `--setting-sources` (unset here, so project settings load) is
# what makes /kit: commands resolve at all: this repo's own tracked
# .claude/settings.json registers the marketplace and enables the plugin as
# project config, the same registration every interactive session against
# this checkout already relies on. --settings below only layers the
# permission grant on top; it is not what makes the plugin resolve.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_SETTINGS="$SCRIPT_DIR/ship-settings.json"
SETTINGS_FILE="$(mktemp -t ship-startable-settings.XXXXXX)"

python3 - "$BASE_SETTINGS" "${PROJECT_SETTINGS:-}" >"$SETTINGS_FILE" <<'PY'
import json, sys
base_path = sys.argv[1]
project_path = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else ""
with open(base_path) as f:
    merged = json.load(f)
if project_path:
    with open(project_path) as f:
        extra = json.load(f)
    perms = merged.setdefault("permissions", {})
    eperms = extra.get("permissions", {})
    for key in ("allow", "deny"):
        combined = list(perms.get(key, []))
        for item in eperms.get(key, []):
            if item not in combined:
                combined.append(item)
        perms[key] = combined
json.dump(merged, sys.stdout, indent=2)
PY

# --- logging -----------------------------------------------------------
LOGDIR="$HOME/.claude/logs/ship-startable"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/$(date +%Y%m%d-%H%M%S)-${LABEL}.log"
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG"; }

log "starting: label=${LABEL} repo=${REPO} max=${MAX} poll-seconds=${POLL_SECONDS} model=${MODEL}"

# A per-ticket or list call that returns in under this floor with nothing to
# show is the failure docs/tending-on-a-runner.md calls the worst kind: the
# process exited fast having done nothing, which looks identical to a clean
# "nothing startable" unless something asserts on the duration.
MIN_SECONDS=5

# --- state ---------------------------------------------------------------
SHIPPED=()
PARKED=()
ANOMALIES=()
TRACKED_OPEN_PRS=()
STOP_REASON=""
REPORTED=0

report_and_exit() {
  [ "$REPORTED" -eq 1 ] && return
  REPORTED=1
  {
    echo "---"
    echo "ship-startable summary (label: $LABEL)"
    echo "shipped: ${#SHIPPED[@]}"
    for e in "${SHIPPED[@]+"${SHIPPED[@]}"}"; do echo "  $e"; done
    echo "parked: ${#PARKED[@]}"
    for e in "${PARKED[@]+"${PARKED[@]}"}"; do echo "  #$e"; done
    if [ "${#ANOMALIES[@]}" -gt 0 ]; then
      echo "anomalies: ${#ANOMALIES[@]}"
      for e in "${ANOMALIES[@]}"; do echo "  $e"; done
    fi
    if [ "${#TRACKED_OPEN_PRS[@]}" -gt 0 ]; then
      echo "still open when the run ended: ${TRACKED_OPEN_PRS[*]}"
    fi
    echo "ended: ${STOP_REASON:-interrupted}"
    echo "log: $LOG"
  } | tee -a "$LOG"
}

on_exit() {
  rm -f "$SETTINGS_FILE"
  [ -n "$STOP_REASON" ] || STOP_REASON="interrupted"
  report_and_exit
}
trap on_exit EXIT INT TERM

# --- helpers ---------------------------------------------------------------

# Invokes claude -p with the merged settings, timing and logging the call.
# Sets TIMED_OUT and TIMED_ELAPSED; what counts as too-fast-to-be-real differs
# per caller (list_lowest_startable tolerates an empty result if it took real
# time, ship_one never should), so the floor check stays with the caller.
run_claude_timed() { # prompt
  local start end
  start=$(date +%s)
  TIMED_OUT="$("$CLAUDE_BIN" -p "$1" --model "$MODEL" --settings "$SETTINGS_FILE" 2>>"$LOG" </dev/null)"
  end=$(date +%s)
  TIMED_ELAPSED=$((end - start))
  printf '%s\n' "$TIMED_OUT" >>"$LOG"
}

# Prints "<pr-number> <state>" for the PR belonging to issue <n>, or nothing.
# Resolves the exact branch from `git worktree list --porcelain` first — the
# convention kit:worktree-conventions documents and worktree-reclaim.sh's own
# account_branch() relies on — so the common case is one targeted `gh pr list
# --head` call rather than scanning every PR ever opened. Falls back to a
# branch-prefix scan only when no live worktree matches (the worktree was
# already reclaimed by the time this runs), never to ship-ticket's own report
# text — the same "don't parse the prose" reasoning that motivated #99.
pr_for_issue() {
  local n="$1" branch pr_info
  branch="$(git worktree list --porcelain 2>/dev/null | awk -v n="$n" '
    /^branch refs\/heads\// {
      b = $0; sub("^branch refs/heads/", "", b)
      if (index(b, n "-") == 1) { print b; exit }
    }')"

  if [ -n "$branch" ]; then
    pr_info="$(gh pr list --head "$branch" --state all --json number,state --limit 1 2>/dev/null |
      python3 -c "
import json, sys
try:
    prs = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if prs:
    print(prs[0]['number'], prs[0]['state'])
")"
    if [ -n "$pr_info" ]; then
      printf '%s\n' "$pr_info"
      return
    fi
  fi

  gh pr list --state all --json number,headRefName,state --limit 200 2>/dev/null |
    python3 -c "
import json, sys
prefix = sys.argv[1] + '-'
try:
    prs = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for pr in prs:
    if pr.get('headRefName', '').startswith(prefix):
        print(pr['number'], pr['state'])
        break
" "$n"
}

# Sets LIST_RESULT (lowest startable issue number, or empty) and LIST_ANOMALY.
list_lowest_startable() {
  run_claude_timed "/kit:list ${LABEL}"
  LIST_ANOMALY=0
  if [ "$TIMED_ELAPSED" -lt "$MIN_SECONDS" ] && [ -z "$TIMED_OUT" ]; then
    LIST_ANOMALY=1
  fi
  LIST_RESULT="$(printf '%s\n' "$TIMED_OUT" | grep -oE '#[0-9]+' | head -1 | tr -d '#')"
}

# Runs one ticket to an open PR (or a park) in its own process. Sets
# SHIP_OUTCOME to "shipped:<pr>:<state>:<hold-or-empty>", "parked", or
# "anomaly". The hold flag matters as much as the PR number does — a PR
# carrying kit-hold is one the CI gate skips entirely and a human has to
# walk through, and reporting it the same as an ordinary shipped ticket would
# bury exactly the PRs the operator most needs to notice.
ship_one() {
  local n="$1" labels pr_info pr_num pr_state pr_labels hold

  run_claude_timed "/kit:ship-ticket ${n} unattended"
  if [ "$TIMED_ELAPSED" -lt "$MIN_SECONDS" ]; then
    SHIP_OUTCOME="anomaly"
    return
  fi

  # kit:startable-tickets condition 4 already excludes a kit-blocked ticket
  # from being offered, so the label appearing now means this call parked it.
  labels="$(gh issue view "$n" --json labels -q '.labels[].name' 2>/dev/null)"
  if printf '%s\n' "$labels" | grep -qx kit-blocked; then
    SHIP_OUTCOME="parked"
    return
  fi

  pr_info="$(pr_for_issue "$n")"
  if [ -n "$pr_info" ]; then
    read -r pr_num pr_state <<<"$pr_info"
    pr_labels="$(gh pr view "$pr_num" --json labels -q '.labels[].name' 2>/dev/null)"
    hold=""
    printf '%s\n' "$pr_labels" | grep -qx kit-hold && hold="hold"
    SHIP_OUTCOME="shipped:${pr_num}:${pr_state}:${hold}"
    return
  fi

  SHIP_OUTCOME="anomaly"
}

# --- main loop ---------------------------------------------------------
SHIP_COUNT=0
while true; do
  list_lowest_startable

  if [ "$LIST_ANOMALY" -eq 1 ]; then
    ANOMALIES+=("/kit:list returned in under ${MIN_SECONDS}s with no output")
    STOP_REASON="stopped: /kit:list did not behave like a resolved plugin command — check plugin registration before retrying"
    break
  fi

  if [ -z "$LIST_RESULT" ]; then
    if [ "${#TRACKED_OPEN_PRS[@]}" -gt 0 ]; then
      open_now="$(gh pr list --state open --json number -q '.[].number' --limit 200 2>/dev/null)"
      still_open=()
      for pr in "${TRACKED_OPEN_PRS[@]}"; do
        printf '%s\n' "$open_now" | grep -qx "$pr" && still_open+=("$pr")
      done
      TRACKED_OPEN_PRS=("${still_open[@]+"${still_open[@]}"}")
    fi

    if [ "${#TRACKED_OPEN_PRS[@]}" -eq 0 ]; then
      STOP_REASON="done: nothing startable under '${LABEL}' and nothing this run opened is still open"
      break
    fi

    log "nothing startable right now; waiting on: ${TRACKED_OPEN_PRS[*]}"
    sleep "$POLL_SECONDS"
    continue
  fi

  log "taking #${LIST_RESULT}"
  ship_one "$LIST_RESULT"
  case "$SHIP_OUTCOME" in
    shipped:*)
      IFS=: read -r _ pr_num pr_state hold_flag <<<"$SHIP_OUTCOME"
      if [ "$hold_flag" = "hold" ]; then
        SHIPPED+=("#${LIST_RESULT} -> PR #${pr_num} (${pr_state}, kit-hold — needs a walkthrough)")
      else
        SHIPPED+=("#${LIST_RESULT} -> PR #${pr_num} (${pr_state})")
      fi
      [ "$pr_state" = "OPEN" ] && TRACKED_OPEN_PRS+=("$pr_num")
      log "shipped #${LIST_RESULT} as PR #${pr_num}${hold_flag:+ [kit-hold]}"
      ;;
    parked)
      PARKED+=("$LIST_RESULT")
      log "parked #${LIST_RESULT}"
      ;;
    anomaly)
      ANOMALIES+=("#${LIST_RESULT}: ship-ticket call returned too fast with no traceable result")
      log "ANOMALY on #${LIST_RESULT} — see ${LOG}"
      ;;
  esac

  SHIP_COUNT=$((SHIP_COUNT + 1))
  if [ "$SHIP_COUNT" -ge "$MAX" ]; then
    STOP_REASON="stopped: shipped-per-run cap (${MAX}) reached"
    break
  fi
done

exit 0
