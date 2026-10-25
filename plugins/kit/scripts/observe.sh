#!/usr/bin/env bash
set -uo pipefail

# Appends, lists, re-checks and clears down the observation store — the drawer a
# pass writes what it learned into instead of asking the user about it.
#
# This is a script rather than prose in each producing pass for one reason: the
# store is JSONL, one record per line, and two of a record's fields are captured
# command output and a free-text paragraph. Both routinely carry newlines,
# quotes and backslashes. A model hand-building that JSON eventually breaks a
# line, and nothing can catch it — the store is excluded from version control
# and lives outside the repo, so `scripts/lint.sh` never sees a record. Here it
# gets `bash -n` from lint and `tests/observe.sh` from CI.
#
# It also runs the check itself. A producer that supplied its own `witness`
# could hand over an answer the command never gave, and the whole value of the
# pair is that a later reader can re-run one and diff the other.

usage() {
  cat >&2 <<'USAGE'
usage:
  observe.sh --by <pass> --claim <text> --check <command> \
             --surfaced <text> --action <text> \
             --who <role> --affected <text> [--issue N] [--pr N]
  observe.sh list
  observe.sh recheck [<slug> ...]
  observe.sh rewitness <slug> [<slug> ...]
  observe.sh drop <slug> [<slug> ...]
USAGE
}

die() { echo "observe.sh: $*" >&2; exit 1; }
misuse() { echo "observe.sh: $*" >&2; usage; exit 2; }

# --- where the store lives ----------------------------------------------

# --git-common-dir points at the *main* repo's .git from inside any worktree.
# --show-toplevel would put the store in the worktree, where it dies with the
# ticket that produced it — which is the moment it was relied on to survive.
# Resolved the long way round rather than with --path-format, which is git 2.31+
# and this suite runs on whatever git the runner ships.
common="$(git rev-parse --git-common-dir 2>/dev/null)" \
  || die "not in a git repository"
case "$common" in
  /*) ;;
   *) common="$(cd "$(git rev-parse --show-toplevel)" && cd "$common" && pwd)" ;;
esac
MAIN_ROOT="$(dirname "$common")"
STORE="$MAIN_ROOT/.claude/observations.jsonl"
REL=".claude/observations.jsonl"

# `.gitignore` would itself be a tracked change in every PR diff of a project
# that commits `.claude/`. Asked of the main checkout, because that is the tree
# the store sits in — a worktree's own exclude file would not cover it.
ensure_excluded() {
  git -C "$MAIN_ROOT" check-ignore -q "$REL" 2>/dev/null && return 0
  mkdir -p "$common/info"
  echo "$REL" >> "$common/info/exclude"
}

count() { grep -c . "$STORE" 2>/dev/null || echo 0; }

# A check runs under a plain `bash -c`, where a command that was only a function
# in the producing session (Claude Code's `rg`) does not exist, and bash's own
# "command not found" becomes a witness that never moves. bash calls
# command_not_found_handle for each name it cannot resolve, pipelines and
# subshells included, so it names exactly what was missing. Matching the phrase
# in the output instead would refuse a check that legitimately greps for it.
# The hook arrived in bash 4, and macOS's /bin/bash is 3.2, where it silently
# never fires — so an older bash is refused rather than trusted. Dispatch calls
# this once for every mode that runs a check, so no caller can forget it.
MISSING=""
init_checks() {
  local major
  major="$(bash -c 'printf %s "${BASH_VERSINFO[0]}"' 2>/dev/null)"
  [ "${major:-0}" -ge 4 ] 2>/dev/null \
    || die "the bash that runs checks is ${major:-unknown}.x, which cannot tell a missing command from a check that ran; put bash 4 or later ahead of it on PATH (macOS: brew install bash)"
  MISSING="$(mktemp "${TMPDIR:-/tmp}/observe-missing.XXXXXX")" \
    || die "could not create a temporary file to detect missing commands"
  trap 'rm -f "$MISSING"' EXIT
}

# Prints the check's output, and fails when the check named a command bash could
# not find — `missing` then says which. The handler is exported so a nested
# `bash -c` reports through it too. `exec` and `env` resolve a command without the
# handler, and exit 127, the status reserved for a command not found, so that
# status alone counts as missing when the handler named nothing.
run_in() { # dir check
  : > "$MISSING"
  (cd "$1" && OBS_MISSING="$MISSING" bash -c '
command_not_found_handle() {
  printf "%s\n" "$1" >> "$OBS_MISSING"
  printf "bash: %s: command not found\n" "$1" >&2
  return 127
}
export -f command_not_found_handle
'"$2" 2>&1)
  [ $? -ne 127 ] || [ -s "$MISSING" ] || echo "a command (exit 127)" > "$MISSING"
  [ ! -s "$MISSING" ]
}

missing() { sort -u "$MISSING" | paste -sd, - | sed 's/,/, /g'; }

# Run a check where it will be re-run: the main checkout the claim is about,
# never the worktree the producing pass happens to be standing in.
run_check() { run_in "$MAIN_ROOT" "$1"; }

# A witness is compared across edits that do not touch the claim, and the commonest
# one is a line shifting: `grep -n` prints `42:text` and the same text at 57 is the
# same answer. Strip the number, leave the text, so only a changed answer is moved.
# Only a check that asks grep for line numbers has any to strip: elsewhere a leading
# `3-column` or `2026-10-24` is the answer, and unnumbering it would hide a change.
# Covers `N:text`, `N-text` (context lines) and `file:N:text`; `file-N-text` context
# lines are left alone, since a dash in a filename cannot be told from the separator.
unnumber() {
  if printf '%s' "$1" | grep -Eq 'grep.*([[:space:]]-[A-Za-z]*n|--line-number)'; then
    sed -E -e 's/^[0-9]+([:-])/\1/' -e 's/^([^:[:space:]]+):[0-9]+:/\1:/'
  else
    cat
  fi
}

# --- reading ------------------------------------------------------------

# Every mode tolerates a line that will not parse. Nothing validates the store
# on write except this script, so one corrupt record must not strand the drawer.
readers() {
  python3 - "$STORE" "$@" <<'PY'
import json, sys

path, mode = sys.argv[1], sys.argv[2]
want = set(sys.argv[3:])

records, broken = [], []
try:
    with open(path) as fh:
        for n, line in enumerate(fh, 1):
            if not line.strip():
                continue
            try:
                records.append(json.loads(line))
            except Exception:
                broken.append(n)
except FileNotFoundError:
    pass

def plural(n):
    return f"{n} observation{'' if n == 1 else 's'}"

if mode == "list":
    if not records and not broken:
        print(f"no observations in {path}")
    else:
        for r in records:
            claim = (r.get("claim") or "").strip().splitlines()
            print(f"{r.get('id','?'):<48}  {r.get('at','?')}  {claim[0] if claim else ''}")
        print(f"{plural(len(records))} in {path}")
        if broken:
            print(f"{len(broken)} unreadable line(s) skipped: "
                  + ", ".join(map(str, broken)), file=sys.stderr)

elif mode == "checks":
    # NUL-separated so the shell can re-run each check without re-parsing JSON.
    # It is the one byte a claim, a command or captured output cannot contain.
    for r in records:
        if want and r.get("id") not in want:
            continue
        for f in ("id", "claim", "check", "witness"):
            sys.stdout.write((r.get(f) or "") + "\0")

elif mode == "rewitness":
    # Pairs of id, new witness, NUL-separated, in the file named by OBS_PAIRS.
    import os
    parts = open(os.environ["OBS_PAIRS"]).read().split("\0")
    new = {parts[i]: parts[i + 1] for i in range(0, len(parts) - 1, 2)}
    for r in records:
        if r.get("id") in new:
            w = new[r["id"]]
            r["witness"] = w if len(w) <= 4000 else w[:4000] + "\n… truncated"
        print(json.dumps(r, ensure_ascii=False))

elif mode == "drop":
    missing = want - {r.get("id") for r in records}
    if missing:
        print("missing:" + ",".join(sorted(missing)), file=sys.stderr)
        sys.exit(1)
    for r in records:
        if r.get("id") not in want:
            print(json.dumps(r, ensure_ascii=False))
PY
}

# --- the append ---------------------------------------------------------

append() {
  local by="" claim="" check="" surfaced="" action="" who="" affected="" issue="" pr=""
  while [ $# -gt 0 ]; do
    # Every flag takes a value, and `shift 2` with one argument left shifts
    # nothing, so a trailing flag would spin here forever.
    case "$1" in --*) [ $# -ge 2 ] || misuse "$1 needs a value" ;; esac
    case "$1" in
      --by)       by="${2-}";       shift 2 ;;
      --claim)    claim="${2-}";    shift 2 ;;
      --check)    check="${2-}";    shift 2 ;;
      --surfaced) surfaced="${2-}"; shift 2 ;;
      --action)   action="${2-}";   shift 2 ;;
      --who)      who="${2-}";      shift 2 ;;
      --affected) affected="${2-}"; shift 2 ;;
      --issue)    issue="${2-}";    shift 2 ;;
      --pr)       pr="${2-}";       shift 2 ;;
      *) misuse "unknown argument: $1" ;;
    esac
  done

  # Each of these is load-bearing for a reader who was not in the session, so a
  # record missing one is refused rather than written half-formed.
  [ -n "$by" ]       || misuse "--by is required: the pass that observed this"
  [ -n "$claim" ]    || misuse "--claim is required: what the repo can contradict"
  [ -n "$check" ]    || misuse "--check is required: the command that tests the claim"
  [ -n "$surfaced" ] || misuse "--surfaced is required: the thread that exposed it"
  [ -n "$action" ]   || misuse "--action is required: where this should end up"
  [ -n "$who" ]      || misuse "--who is required: who gets a wrong result (visitor, owner, operator, agent), or nobody"
  [ -n "$affected" ] || misuse "--affected is required: what they do, and what they get instead of what they expect"

  # A finding that affects nobody is re-checked at every triage and buries the
  # ones that do. Exit 0 and print, never refuse: a usage error invites the
  # producer to retry until something is written, and the printed line rides the
  # "report the line it prints" rule every producer already follows.
  local who_norm
  who_norm="$(printf '%s' "$who" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ "$who_norm" = nobody ]; then
    printf 'dropped — %s: affects nobody (%s)\n' "$claim" "$affected"
    return 0
  fi

  local branch repo
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  repo="$(git config --get remote.origin.url 2>/dev/null \
          | sed -e 's#.*[:/]\([^/]*/[^/]*\)$#\1#' -e 's#\.git$##')"
  # The kit's own branch layout. A project whose branches are named otherwise
  # passes --issue, which wins.
  [ -n "$issue" ] || issue="$(printf '%s' "$branch" | sed -n 's/^\([0-9][0-9]*\)-.*/\1/p')"

  # A worktree is deleted when its ticket merges, and the check is re-run from the
  # main checkout: a check naming one reads as moved forever, whatever the repo says.
  case "$check" in
    *.claude/worktrees/*) misuse "--check names a worktree path; it is re-run from the main checkout, so write it relative to the repo root" ;;
  esac

  # Run it here, not inside the python call, so a check that could not run can be
  # refused. An empty answer is kept: an absence is a valid witness.
  # Run where the pass is standing, not in the main checkout: the claim is usually
  # about code the pass's own branch added, which main does not have until it merges.
  # (Running it in main wrote an empty witness for every such claim.) Recheck runs it
  # in main later, so the record reads as moved until the PR lands, then holds.
  local witness
  witness="$(run_in "$(git rev-parse --show-toplevel)" "$check")" || misuse "--check runs $(missing), which a plain bash -c cannot find (a session's shell function is not a command there); write it with commands that are, such as grep -rn for rg"

  case "$witness" in
    *"No such file or directory"*) misuse "--check reads a path that does not exist here; a witness that is already an error can never read as gone later" ;;
  esac

  ensure_excluded
  mkdir -p "$(dirname "$STORE")"

  # One interpreter for the whole append: it reads the store for taken slugs,
  # derives a free one, writes the record, and reports what the caller prints.
  OBS_STORE="$STORE" OBS_BY="$by" OBS_CLAIM="$claim" OBS_CHECK="$check" \
  OBS_WITNESS="$witness" OBS_SURFACED="$surfaced" \
  OBS_ACTION="$action" OBS_WHO="$who" OBS_AFFECTED="$affected" OBS_REPO="$repo" OBS_BRANCH="$branch" \
  OBS_ISSUE="$issue" OBS_PR="$pr" \
  python3 - <<'PY'
import datetime, json, os, re

store = os.environ["OBS_STORE"]

taken, kept = set(), 0
try:
    with open(store) as fh:
        for line in fh:
            if not line.strip():
                continue
            kept += 1
            try:
                taken.add(json.loads(line).get("id"))
            except Exception:
                pass
except FileNotFoundError:
    pass

claim = os.environ["OBS_CLAIM"]
slug = re.sub(r"[^a-z0-9]+", "-", claim.lower()).strip("-")[:48].strip("-") or "observation"
obs_id, n = slug, 1
while obs_id in taken:
    n += 1
    obs_id = f"{slug}-{n}"

def num(key):
    v = os.environ.get(key, "").strip()
    return int(v) if v.isdigit() else None

# A whole file pasted into a record makes the store unreadable and the diff at
# triage useless. A check that prints this much is the wrong check.
witness = os.environ["OBS_WITNESS"]
LIMIT = 4000
if len(witness) > LIMIT:
    witness = witness[:LIMIT] + "\n… truncated"

record = {
    "v": 2,
    "id": obs_id,
    "at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
    "by": os.environ["OBS_BY"],
    "ctx": {
        "repo": os.environ.get("OBS_REPO") or None,
        "issue": num("OBS_ISSUE"),
        "branch": os.environ.get("OBS_BRANCH") or None,
        "pr": num("OBS_PR"),
    },
    "claim": claim,
    "who": os.environ["OBS_WHO"],
    "affected": os.environ["OBS_AFFECTED"],
    "check": os.environ["OBS_CHECK"],
    "witness": witness,
    "surfaced": os.environ["OBS_SURFACED"],
    "action": os.environ["OBS_ACTION"],
}
with open(store, "a") as fh:
    fh.write(json.dumps(record, ensure_ascii=False) + "\n")

total = kept + 1
print(f"observed {obs_id} — {claim}")
print(f"{total} observation{'' if total == 1 else 's'} in {store}")
PY
}

# --- the readers --------------------------------------------------------

# Re-running the check is what replaces a staleness timer. A witness the repo
# has moved past means the observation was either acted on or was wrong, and
# either way it can die without anyone adjudicating it.
do_recheck() {
  local any=0 id claim check was now
  while IFS= read -r -d '' id    && IFS= read -r -d '' claim \
     && IFS= read -r -d '' check && IFS= read -r -d '' was; do
    any=1
    if ! now="$(run_check "$check")"; then
      # Checked before the diff: a record written before the refusal carries the
      # error as its witness, and would otherwise read as holding forever.
      printf 'unrunnable  %s  %s\n' "$id" "$claim"
      printf '       missing: %s\n' "$(missing)"
    elif [ "$(printf '%s' "$now" | unnumber "$check")" = "$(printf '%s' "$was" | unnumber "$check")" ]; then
      printf 'holds  %s  %s\n' "$id" "$claim"
    elif printf '%s' "$now" | grep -q 'No such file or directory' \
         && ! printf '%s' "$was" | grep -q 'No such file or directory'; then
      # The path the check reads is gone, so the check can no longer answer. That is
      # not evidence about the claim either way: rewrite the check or drop the record.
      printf 'gone   %s  %s\n' "$id" "$claim"
      printf '       now: %s\n' "$now" | sed -n '1,3p'
    else
      printf 'moved  %s  %s\n' "$id" "$claim"
      printf '       was: %s\n' "$was" | sed -n '1,10p'
      printf '       now: %s\n' "$now" | sed -n '1,10p'
    fi
  done < <(readers checks "$@")
  [ "$any" = 1 ] || echo "no observations in $STORE"
}

# Re-capture the witness of records whose check could not answer when they were
# written — typically a claim about code still in an unmerged PR, which main lacked
# and so witnessed as empty. Runs the check from the main checkout, where recheck
# will, so the record holds from here until the repo moves. It does not judge the
# claim: a record rewitnessed is a record whose recheck means something again.
# A check that cannot run is skipped, for the reason it is refused at write.
do_rewitness() {
  [ $# -gt 0 ] || misuse "rewitness needs at least one slug"
  [ -f "$STORE" ] || die "no observations in $STORE"
  local id claim check was now pairs n=0 skipped=0
  pairs="$(mktemp "$STORE.pairs.XXXXXX")"
  while IFS= read -r -d '' id    && IFS= read -r -d '' claim \
     && IFS= read -r -d '' check && IFS= read -r -d '' was; do
    if ! now="$(run_check "$check")"; then
      skipped=$((skipped + 1)); printf 'skipped %s — check runs %s, which cannot be found\n' "$id" "$(missing)" >&2
    else
      printf '%s\0%s\0' "$id" "$now" >> "$pairs"; n=$((n + 1))
    fi
  done < <(readers checks "$@")
  # `readers checks` ignores slugs it does not know, so count what it found.
  if [ $((n + skipped)) -ne $# ]; then
    rm -f "$pairs"; die "no such observation among: $*"
  fi
  local tmp; tmp="$(mktemp "$STORE.XXXXXX")"
  if ! OBS_PAIRS="$pairs" readers rewitness > "$tmp"; then
    rm -f "$pairs" "$tmp"; die "could not rewrite $STORE"
  fi
  rm -f "$pairs"; mv "$tmp" "$STORE"
  printf 'rewitnessed %d, skipped %d — %s in %s\n' "$n" "$skipped" "$(count) observations" "$STORE"
}

# The only write that is not a single-line append, so it is the only one that
# can lose the store. Rewrite a temp file and move it into place.
do_drop() {
  [ $# -gt 0 ] || misuse "drop needs at least one slug"
  [ -f "$STORE" ] || die "no observations in $STORE"
  local tmp err; tmp="$(mktemp "$STORE.XXXXXX")"; err="$tmp.err"
  if ! readers drop "$@" > "$tmp" 2>"$err"; then
    local missing; missing="$(sed -n 's/^missing://p' "$err")"
    rm -f "$tmp" "$err"
    die "no such observation: ${missing:-$*}"
  fi
  rm -f "$err"
  mv "$tmp" "$STORE"
  printf 'dropped %s — %s left\n' "$*" "$(count)"
}

# --- dispatch -----------------------------------------------------------

case "${1-}" in
  "")      misuse "nothing to do" ;;
  list)    readers list ;;
  recheck) shift; init_checks; do_recheck "$@" ;;
  rewitness) shift; init_checks; do_rewitness "$@" ;;
  drop)    shift; do_drop "$@" ;;
  -h|--help) usage; exit 0 ;;
  *)       init_checks; append "$@" ;;
esac
