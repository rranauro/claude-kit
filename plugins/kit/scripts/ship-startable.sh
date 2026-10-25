#!/usr/bin/env bash
# Ship every startable ticket under a label, one process each — the runner
# ship-ticket.md names as "#101": a fresh `claude -p` per ticket, so no ticket
# ever runs in a context that carried a previous one. See
# docs/shipping-on-a-runner.md for the gotchas this works around.
#
#   ship-startable.sh <label> [--repo DIR] [--max N] [--poll-seconds N]
#                     [--project-settings FILE] [--model NAME] [--bg]
#                     [--observations]
#
# --max caps tickets shipped in one run (default 20) — the safety valve if the
# startable check is ever wrong; the run stops and says so rather than opening
# PRs without bound.
# --poll-seconds is how often the run re-checks after finding nothing
# startable while a PR it opened is still open (default 120) — short enough to
# notice a blocker closing well inside the ~15-minute round trip #101's own
# text observed. Not meant to be tuned; the flag exists for the rare case a
# consuming project's CI is unusually slow or fast.
# --bg runs every call as a `claude --bg` session instead of `claude -p`, in
# don't-ask mode so the grant stays the boundary. A background session has no
# stdout, so /kit:list writes its offer block to a file this run names.
# --observations (implies --bg) drains the observation store once the label has
# nothing startable: one record waiting on a ticket is filed, shipped by number,
# and dropped once its issue has a PR or a park, before the next is filed — so
# the tracker never holds the queue. See docs/shipping-on-a-runner.md.
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

. "$(dirname "${BASH_SOURCE[0]}")/default-model.sh"

LABEL=""
REPO="$PWD"
MAX=20
POLL_SECONDS=120
PROJECT_SETTINGS=""
MODEL="${SHIP_STARTABLE_MODEL:-$KIT_DEFAULT_MODEL}"
BG=0
OBS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)             REPO="$2"; shift 2 ;;
    --max)               MAX="$2"; shift 2 ;;
    --poll-seconds)      POLL_SECONDS="$2"; shift 2 ;;
    --project-settings)  PROJECT_SETTINGS="$2"; shift 2 ;;
    --model)             MODEL="$2"; shift 2 ;;
    --bg)                BG=1; shift ;;
    --observations)      OBS=1; BG=1; shift ;;
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
  echo "usage: ship-startable.sh <label> [--repo DIR] [--max N] [--poll-seconds N] [--project-settings FILE] [--model NAME] [--bg] [--observations]" >&2
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
# --settings carries the permission grant only. What makes /kit: commands
# resolve is --plugin-dir below: print mode does not load the project setting
# source, so however the plugin reaches an interactive session against the
# target repo — an inline .claude/ plugin, an enabled marketplace entry — none
# of it is in scope here, and /kit:list comes back "Unknown command".
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# This script lives in the plugin it has to load, so the plugin root is its
# own parent — correct from any checkout, with nothing registered anywhere.
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
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

# Filing is the one call that creates an issue, and ship-settings.json denies
# that on purpose: a ship pass that files is the backlog drawer ADR 0008
# rejects. So filing gets a grant of its own, taken as written — a project's
# test and lint commands have nothing to do there.
FILE_SETTINGS="$SCRIPT_DIR/file-settings.json"
OBSERVE="$SCRIPT_DIR/observe.sh"

# Where a background session leaves the answer this run has to read. Passed to
# every session with --add-dir, since it sits outside the repository.
REPLY_DIR="$(mktemp -d -t ship-startable-replies.XXXXXX)"

# --- logging -----------------------------------------------------------
LOGDIR="$HOME/.claude/logs/ship-startable"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/$(date +%Y%m%d-%H%M%S)-${LABEL}.log"
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG"; }

# Announced before any work, not only in the exit summary: a run killed hard
# enough to skip the EXIT trap — a closed terminal, a SIGKILL, a machine that
# slept — leaves an operator with no way to find what it wrote.
log "log: $LOG"
log "follow it with: tail -f $LOG"

log "starting: label=${LABEL} repo=${REPO} max=${MAX} poll-seconds=${POLL_SECONDS} model=${MODEL} bg=${BG} observations=${OBS}"

# A per-ticket or list call that returns in under this floor with nothing to
# show is the failure docs/tending-on-a-runner.md calls the worst kind: the
# process exited fast having done nothing, which looks identical to a clean
# "nothing startable" unless something asserts on the duration.
MIN_SECONDS=5

# How often a background session is asked whether it is still working. Read
# from the environment only so tests/ship-startable.sh need not wait 15s a call.
BG_POLL="${SHIP_STARTABLE_BG_POLL:-15}"

# --- state ---------------------------------------------------------------
SHIPPED=()
PARKED=()
ANOMALIES=()
DECLINED=()
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
    if [ "$OBS" -eq 1 ]; then
      echo "declined: ${#DECLINED[@]}"
      for e in "${DECLINED[@]+"${DECLINED[@]}"}"; do echo "  $e"; done
      echo "records remaining: $(records_left)"
    fi
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
  rm -rf "$REPLY_DIR"
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
  TIMED_OUT="$("$CLAUDE_BIN" -p "$1" --model "$MODEL" \
    --plugin-dir "$PLUGIN_DIR" --settings "$SETTINGS_FILE" 2>>"$LOG" </dev/null)"
  end=$(date +%s)
  TIMED_ELAPSED=$((end - start))
  printf '%s\n' "$TIMED_OUT" >>"$LOG"
}

# The --bg counterpart of run_claude_timed: launches a background session and
# blocks until it stops working, so the loop paces exactly as it does on -p.
# A session ends its turn as "done" or, when its last message reads as asking
# for something, "blocked" — either way it is finished, and outcomes are read
# from GitHub or the reply file it was told to write, never from what it said.
# Stopped afterwards so idle sessions do not pile up.
run_claude_bg_timed() { # prompt name [settings]
  local start end state
  start=$(date +%s)
  if ! "$CLAUDE_BIN" --bg --name "$2" --model "$MODEL" --plugin-dir "$PLUGIN_DIR" \
      --settings "${3:-$SETTINGS_FILE}" --add-dir "$REPLY_DIR" \
      --permission-mode dontAsk "$1" >>"$LOG" 2>&1 </dev/null; then
    TIMED_ELAPSED=0
    return
  fi
  log "session $2 started — follow it with: claude attach $2"
  while :; do
    sleep "$BG_POLL"
    state="$("$CLAUDE_BIN" agents --json --all 2>/dev/null | python3 -c "
import json, sys
name = sys.argv[1]
try:
    sessions = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(next((s.get('state', '') for s in sessions if s.get('name') == name), 'missing'))
" "$2")"
    [ "$state" = "working" ] || [ -z "$state" ] || break
  done
  end=$(date +%s)
  TIMED_ELAPSED=$((end - start))
  log "session $2 ended ($state) after ${TIMED_ELAPSED}s"
  "$CLAUDE_BIN" stop "$2" >>"$LOG" 2>&1 || true
}

# Prints "<pr-number> <state>" for the PR belonging to issue <n>, or nothing.
# Reads GitHub's own closing-issue link, per kit:startable-tickets
# `already-carried`. A branch prefix would miss a PR opened from a branch that
# carries no issue number and report a cleanly shipped ticket as an anomaly;
# ship-ticket's own report text is out for the "don't parse the prose" reasoning
# that motivated #99.
pr_for_issue() {
  local n="$1"
  gh pr list --state all --json number,state,closingIssuesReferences --limit 200 2>/dev/null |
    python3 -c "
import json, sys
n = int(sys.argv[1])
try:
    prs = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for pr in prs:
    if any(ref.get('number') == n for ref in pr.get('closingIssuesReferences') or []):
        print(pr['number'], pr['state'])
        break
" "$n"
}

# Prints the numbers on the offer block's line for <label>, and exits non-zero
# when the block or that line is absent. Nothing outside the block is read —
# docs/shipping-on-a-runner.md carries why, and giving that back on a loose
# parse of the line itself would undo it.
offer_line() { # reply label
  printf '%s\n' "$1" | awk -v label="$2" '
    $0 == "<!-- kit-startable: begin -->" { inblock = 1; next }
    $0 == "<!-- kit-startable: end -->"   { inblock = 0; next }
    inblock {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (index(line, label ":") != 1) next
      print substr(line, length(label) + 2)
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  '
}

# Sets LIST_RESULT (lowest startable issue number, or empty), LIST_ANOMALY, and
# LIST_UNREADABLE. Empty-with-a-line and no-line-at-all are different answers:
# the first is a drained label, the second is a reply this run cannot act on,
# and collapsing them is what let a mistyped label report a drained backlog.
list_lowest_startable() {
  if [ "$BG" -eq 1 ]; then
    local offer
    offer="$REPLY_DIR/offer-$(date +%s)"
    run_claude_bg_timed "/kit:list ${LABEL} --offer-file ${offer}" "list-${LABEL}-$(date +%s)"
    TIMED_OUT="$(cat "$offer" 2>/dev/null)"
  else
    run_claude_timed "/kit:list ${LABEL}"
  fi
  LIST_ANOMALY=0
  LIST_UNREADABLE=0
  LIST_RESULT=""
  if [ "$TIMED_ELAPSED" -lt "$MIN_SECONDS" ] && [ -z "$TIMED_OUT" ]; then
    LIST_ANOMALY=1
    return
  fi
  local numbers
  if ! numbers="$(offer_line "$TIMED_OUT" "$LABEL")"; then
    LIST_UNREADABLE=1
    return
  fi
  numbers="${numbers#"${numbers%%[![:space:]]*}"}"
  LIST_RESULT="${numbers%%[,[:space:]]*}"
  # Anything but a number where the contract promises one is a line this run
  # cannot act on, not a number to dig out of it.
  case "$LIST_RESULT" in
    "")       ;;
    *[!0-9]*) LIST_RESULT=""; LIST_UNREADABLE=1 ;;
  esac
}

# Runs one ticket to an open PR (or a park) in its own process. Sets
# SHIP_OUTCOME to "shipped:<pr>:<state>:<hold-or-empty>", "parked", or
# "anomaly". The hold flag matters as much as the PR number does — a PR
# carrying kit-hold is one the CI gate skips entirely and a human has to
# take charge of, and reporting it the same as an ordinary shipped ticket would
# bury exactly the PRs the operator most needs to notice.
ship_one() {
  local n="$1" labels pr_info pr_num pr_state pr_labels hold

  if [ "$BG" -eq 1 ]; then
    run_claude_bg_timed "/kit:ship-ticket ${n} unattended" "ship-${n}-$(date +%s)"
  else
    run_claude_timed "/kit:ship-ticket ${n} unattended"
  fi
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

# The store's size, for the summary. observe.sh's own list line is the count,
# so nothing here parses a record.
records_left() {
  local n
  n="$("$OBSERVE" list 2>/dev/null | tail -n 1 | sed -n 's/^\([0-9][0-9]*\) observation.*/\1/p')"
  echo "${n:-0}"
}

# Sets NEXT_RECORD to the oldest record this run may file and has not already
# declined, or empty. Sets FILEABLE_FAILED when observe.sh could not answer — a
# store this run cannot read is not an empty one.
next_record() {
  local slugs slug d skip
  NEXT_RECORD=""
  FILEABLE_FAILED=""
  if ! slugs="$("$OBSERVE" fileable 2>&1)"; then
    FILEABLE_FAILED="$slugs"
    return
  fi
  while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    skip=0
    for d in "${DECLINED[@]+"${DECLINED[@]}"}"; do
      [ "${d%%:*}" = "$slug" ] && skip=1 && break
    done
    [ "$skip" -eq 0 ] && { NEXT_RECORD="$slug"; return; }
  done <<<"$slugs"
}

# Files one record as an issue in its own session, which may decline. Sets
# FILE_OUTCOME to "filed:<n>" or "declined:<reason>". A reply that says neither
# is a decline too: the record stays, and nothing is shipped that this run
# cannot name.
file_one() { # slug
  local reply="$REPLY_DIR/file-$1" first n
  run_claude_bg_timed "/kit:observe file $1 --reply ${reply}" "file-$1-$(date +%s)" "$FILE_SETTINGS"
  first="$(sed -n 1p "$reply" 2>/dev/null)"
  case "$first" in
    "filed: "*)
      n="${first#filed: }"
      case "$n" in
        ""|*[!0-9]*) FILE_OUTCOME="declined:the filing session's reply named no issue number" ;;
        *)           FILE_OUTCOME="filed:$n" ;;
      esac ;;
    "declined: "*) FILE_OUTCOME="declined:${first#declined: }" ;;
    *)             FILE_OUTCOME="declined:the filing session left no reply" ;;
  esac
}

# A filed issue whose ship result cannot be traced would otherwise sit in the
# tracker with nobody carrying it, so the runner parks it in kit:park's shape:
# the comment, then the reason in the body and the label. A comment that did
# not post gets no label, for the reason kit:park gives.
park_filed() { # issue slug
  local reason body
  reason="The runner that filed this from observation \`$2\` started \`/kit:ship-ticket $1 unattended\`, but could trace neither a pull request closing it nor a park. Look for a worktree or branch named for #$1, then remove \`kit-blocked\` to let it be shipped again."
  gh issue comment "$1" --body "<!-- kit-park -->
$reason" >>"$LOG" 2>&1 || { log "could not comment on #$1; it is not parked"; return 1; }
  body="$(gh issue view "$1" --json body -q .body 2>/dev/null)"
  printf '%s\n\n## Blocked by\n\n%s\n' "$body" "$reason" > "$REPLY_DIR/body-$1"
  gh issue edit "$1" --add-label kit-blocked --body-file "$REPLY_DIR/body-$1" >>"$LOG" 2>&1 \
    || log "could not label #$1 kit-blocked; its comment is the only record"
}

# Takes one record through filing and shipping. Sets FED to 1 when a ticket was
# worked, which the caller counts toward --max; a decline works nothing.
feed_one() {
  FED=0
  next_record
  [ -n "$NEXT_RECORD" ] || return 0
  local slug="$NEXT_RECORD" n
  log "filing observation ${slug}"
  file_one "$slug"
  case "$FILE_OUTCOME" in
    declined:*)
      DECLINED+=("${slug}: ${FILE_OUTCOME#declined:}")
      log "declined ${slug}: ${FILE_OUTCOME#declined:}"
      return 0 ;;
  esac
  n="${FILE_OUTCOME#filed:}"
  FED=1
  log "filed ${slug} as #${n}; taking #${n}"
  ship_one "$n"
  case "$SHIP_OUTCOME" in
    shipped:*)
      IFS=: read -r _ pr_num pr_state hold_flag <<<"$SHIP_OUTCOME"
      SHIPPED+=("#${n} -> PR #${pr_num} (${pr_state}${hold_flag:+, kit-hold — needs a person}), from ${slug}")
      [ "$pr_state" = "OPEN" ] && TRACKED_OPEN_PRS+=("$pr_num")
      ;;
    parked)
      PARKED+=("${n} (from ${slug})") ;;
    anomaly)
      ANOMALIES+=("#${n}: ship-ticket call returned with no traceable result")
      if ! park_filed "$n" "$slug"; then
        # Unparked, the record is the only full trace left: keep it.
        log "kept ${slug}: #${n} could not be parked"
        return 0
      fi
      PARKED+=("${n} (from ${slug}; parked by the runner — no result could be traced)") ;;
  esac
  "$OBSERVE" drop "$slug" >>"$LOG" 2>&1 || log "could not drop ${slug} after #${n}"
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

  if [ "$LIST_UNREADABLE" -eq 1 ]; then
    ANOMALIES+=("/kit:list answered with no offer block line for '${LABEL}'")
    STOP_REASON="stopped: /kit:list reply was unreadable — no offer block line for '${LABEL}'; check the label is spelled as it exists and that /kit:list emitted its block"
    break
  fi

  # The label drained: feed it one record, and only one, before asking again —
  # a ticket filed now is shipped before the next record is filed.
  if [ -z "$LIST_RESULT" ] && [ "$OBS" -eq 1 ]; then
    feed_one
    if [ -n "$FILEABLE_FAILED" ]; then
      ANOMALIES+=("observe.sh fileable failed: ${FILEABLE_FAILED}")
      STOP_REASON="stopped: the observation store could not be read — ${FILEABLE_FAILED}"
      break
    fi
    if [ "$FED" -eq 1 ]; then
      SHIP_COUNT=$((SHIP_COUNT + 1))
      if [ "$SHIP_COUNT" -ge "$MAX" ]; then
        STOP_REASON="stopped: shipped-per-run cap (${MAX}) reached"
        break
      fi
      continue
    fi
    [ -n "$NEXT_RECORD" ] && continue
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
        SHIPPED+=("#${LIST_RESULT} -> PR #${pr_num} (${pr_state}, kit-hold — needs a person)")
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
