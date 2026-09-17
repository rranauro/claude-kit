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

# Run a check where it will be re-run: the main checkout the claim is about,
# never the worktree the producing pass happens to be standing in.
run_check() { (cd "$MAIN_ROOT" && bash -c "$1" 2>&1); }

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

  local branch repo
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  repo="$(git config --get remote.origin.url 2>/dev/null \
          | sed -e 's#.*[:/]\([^/]*/[^/]*\)$#\1#' -e 's#\.git$##')"
  # The kit's own branch layout. A project whose branches are named otherwise
  # passes --issue, which wins.
  [ -n "$issue" ] || issue="$(printf '%s' "$branch" | sed -n 's/^\([0-9][0-9]*\)-.*/\1/p')"

  ensure_excluded
  mkdir -p "$(dirname "$STORE")"

  # One interpreter for the whole append: it reads the store for taken slugs,
  # derives a free one, writes the record, and reports what the caller prints.
  OBS_STORE="$STORE" OBS_BY="$by" OBS_CLAIM="$claim" OBS_CHECK="$check" \
  OBS_WITNESS="$(run_check "$check")" OBS_SURFACED="$surfaced" \
  OBS_ACTION="$action" OBS_REPO="$repo" OBS_BRANCH="$branch" \
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
    "v": 1,
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
    now="$(run_check "$check")"
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
  recheck) shift; do_recheck "$@" ;;
  drop)    shift; do_drop "$@" ;;
  -h|--help) usage; exit 0 ;;
  *)       append "$@" ;;
esac
