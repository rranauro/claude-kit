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
             --surfaced <text> --action <text> [--issue N] [--pr N]
  observe.sh list
  observe.sh recheck [<slug> ...]
  observe.sh drop <slug> [<slug> ...]
USAGE
}

die() { echo "observe.sh: $*" >&2; exit 1; }
misuse() { echo "observe.sh: $*" >&2; usage; exit 2; }

# --- where the store lives ----------------------------------------------

# --git-common-dir points at the *main* repo's .git from inside any worktree.
# --show-toplevel would put the store in the worktree, where it dies with the
# ticket that produced it — which is the moment it was relied on to survive.
common="$(git rev-parse --git-common-dir 2>/dev/null)" \
  || die "not in a git repository"
case "$common" in
  /*) ;;
   *) common="$(cd "$(git rev-parse --show-toplevel)" && cd "$common" && pwd)" ;;
esac
MAIN_ROOT="$(dirname "$common")"
STORE="$MAIN_ROOT/.claude/observations.jsonl"
REL=".claude/observations.jsonl"

# Many projects commit `.claude/`, so a rule in `.gitignore` would itself be a
# tracked change showing up in every PR diff. `info/exclude` is per-clone and
# invisible to everyone else. Asked of the main checkout, because that is the
# tree the store sits in.
ensure_excluded() {
  git -C "$MAIN_ROOT" check-ignore -q "$REL" 2>/dev/null && return 0
  mkdir -p "$common/info"
  echo "$REL" >> "$common/info/exclude"
}

count() { [ -f "$STORE" ] && grep -c . "$STORE" || echo 0; }

# --- reading ------------------------------------------------------------

# Every reader tolerates a line that will not parse. Nothing validates the store
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

def first(text):
    text = (text or "").strip()
    return text.splitlines()[0] if text else ""

if mode == "list":
    for r in records:
        print(f"{r.get('id','?')}\t{r.get('at','?')}\t{first(r.get('claim'))}")
    for n in broken:
        print(f"unreadable\tline {n}\tskipped")
    print(f"__count__\t{len(records)}\t{len(broken)}")

elif mode == "ids":
    for r in records:
        print(r.get("id", ""))

elif mode == "checks":
    # One record per line, tab-separated, so the shell can re-run each check
    # without re-parsing JSON. Tabs and newlines inside a field would break
    # that, so the check and the witness go over as JSON strings.
    for r in records:
        if want and r.get("id") not in want:
            continue
        print("\t".join([
            r.get("id", ""),
            json.dumps(r.get("claim", "")),
            json.dumps(r.get("check", "")),
            json.dumps(r.get("witness", "")),
        ]))

elif mode == "drop":
    missing = want - {r.get("id") for r in records}
    if missing:
        print("missing:" + ",".join(sorted(missing)), file=sys.stderr)
        sys.exit(1)
    for r in records:
        if r.get("id") in want:
            continue
        print(json.dumps(r, ensure_ascii=False))
PY
}

# --- the append ---------------------------------------------------------

append() {
  local by="" claim="" check="" surfaced="" action="" issue="" pr=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --by)       by="${2-}";       shift 2 ;;
      --claim)    claim="${2-}";    shift 2 ;;
      --check)    check="${2-}";    shift 2 ;;
      --surfaced) surfaced="${2-}"; shift 2 ;;
      --action)   action="${2-}";   shift 2 ;;
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

  local branch repo witness
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  repo="$(git config --get remote.origin.url 2>/dev/null \
          | sed -e 's#.*[:/]\([^/]*/[^/]*\)$#\1#' -e 's#\.git$##')"
  [ -n "$issue" ] || issue="$(printf '%s' "$branch" | sed -n 's/^\([0-9][0-9]*\)-.*/\1/p')"

  # Run it where it will be re-run: the main checkout the claim is about, never
  # the worktree the producing pass happens to be standing in.
  witness="$(cd "$MAIN_ROOT" && bash -c "$check" 2>&1)"

  ensure_excluded
  mkdir -p "$(dirname "$STORE")"

  local id
  id="$(OBS_CLAIM="$claim" OBS_TAKEN="$( [ -f "$STORE" ] && readers ids || true )" python3 - <<'PY'
import os, re
words = re.sub(r"[^a-z0-9]+", "-", os.environ["OBS_CLAIM"].lower()).strip("-").split("-")
slug = "-".join(w for w in words if w)[:48].strip("-") or "observation"
taken = set(filter(None, os.environ["OBS_TAKEN"].splitlines()))
candidate, n = slug, 1
while candidate in taken:
    n += 1
    candidate = f"{slug}-{n}"
print(candidate)
PY
)"

  OBS_ID="$id" OBS_BY="$by" OBS_CLAIM="$claim" OBS_CHECK="$check" \
  OBS_WITNESS="$witness" OBS_SURFACED="$surfaced" OBS_ACTION="$action" \
  OBS_REPO="$repo" OBS_BRANCH="$branch" OBS_ISSUE="$issue" OBS_PR="$pr" \
  python3 - >> "$STORE" <<'PY'
import datetime, json, os

def num(key):
    v = os.environ.get(key, "").strip()
    return int(v) if v.isdigit() else None

# A whole file pasted into a record makes the store unreadable and the diff at
# triage useless. A check that prints this much is the wrong check.
witness = os.environ["OBS_WITNESS"]
LIMIT = 4000
if len(witness) > LIMIT:
    witness = witness[:LIMIT] + "\n… truncated"

print(json.dumps({
    "v": 1,
    "id": os.environ["OBS_ID"],
    "at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
    "by": os.environ["OBS_BY"],
    "ctx": {
        "repo": os.environ.get("OBS_REPO") or None,
        "issue": num("OBS_ISSUE"),
        "branch": os.environ.get("OBS_BRANCH") or None,
        "pr": num("OBS_PR"),
    },
    "claim": os.environ["OBS_CLAIM"],
    "check": os.environ["OBS_CHECK"],
    "witness": witness,
    "surfaced": os.environ["OBS_SURFACED"],
    "action": os.environ["OBS_ACTION"],
}, ensure_ascii=False))
PY

  local n; n="$(count)"
  printf 'observed %s — %s\n' "$id" "$claim"
  printf '%s %s in %s\n' "$n" "$( [ "$n" = 1 ] && echo observation || echo observations )" "$STORE"
}

# --- the readers --------------------------------------------------------

do_list() {
  local n=0 broken=0
  while IFS=$'\t' read -r a b c; do
    if [ "$a" = "__count__" ]; then n="$b"; broken="$c"; continue; fi
    printf '%-48s  %s  %s\n' "$a" "$b" "$c"
  done < <(readers list)
  if [ "$n" = 0 ] && [ "$broken" = 0 ]; then
    echo "no observations in $STORE"
  else
    printf '%s %s in %s\n' "$n" "$( [ "$n" = 1 ] && echo observation || echo observations )" "$STORE"
    [ "$broken" = 0 ] || echo "$broken unreadable line(s) skipped" >&2
  fi
}

# Re-running the check is what replaces a staleness timer. A witness the repo
# has moved past means the observation was either acted on or was wrong, and
# either way it can die without anyone adjudicating it.
do_recheck() {
  local any=0
  while IFS=$'\t' read -r id claim_j check_j witness_j; do
    [ -n "$id" ] || continue
    any=1
    local claim check was now
    claim="$(printf '%s' "$claim_j" | python3 -c 'import json,sys; print(json.load(sys.stdin))')"
    check="$(printf '%s' "$check_j" | python3 -c 'import json,sys; print(json.load(sys.stdin))')"
    was="$(printf '%s' "$witness_j" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin))')"
    now="$(cd "$MAIN_ROOT" && bash -c "$check" 2>&1)"
    if [ "$now" = "$was" ]; then
      printf 'holds  %s  %s\n' "$id" "$claim"
    else
      printf 'moved  %s  %s\n' "$id" "$claim"
      printf '       was: %s\n' "$was" | sed -n '1,10p'
      printf '       now: %s\n' "$now" | sed -n '1,10p'
    fi
  done < <(readers checks "$@")
  [ "$any" = 1 ] || echo "no observations in $STORE"
}

# The only write that is not a single-line append, so it is the only one that
# can lose the store. Rewrite a temp file and move it into place.
do_drop() {
  [ $# -gt 0 ] || misuse "drop needs at least one slug"
  [ -f "$STORE" ] || die "no observations in $STORE"
  local tmp; tmp="$(mktemp "$STORE.XXXXXX")"
  if ! readers drop "$@" > "$tmp" 2>"$tmp.err"; then
    local missing; missing="$(sed -n 's/^missing://p' "$tmp.err")"
    rm -f "$tmp" "$tmp.err"
    die "no such observation: ${missing:-$*}"
  fi
  rm -f "$tmp.err"
  mv "$tmp" "$STORE"
  printf 'dropped %s — %s left\n' "$*" "$(count)"
}

# --- dispatch -----------------------------------------------------------

case "${1-}" in
  "")      misuse "nothing to do" ;;
  list)    shift; do_list "$@" ;;
  recheck) shift; do_recheck "$@" ;;
  drop)    shift; do_drop "$@" ;;
  -h|--help) usage; exit 0 ;;
  *)       append "$@" ;;
esac
