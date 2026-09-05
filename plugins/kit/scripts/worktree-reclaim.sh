#!/usr/bin/env bash
# Reclaim git worktrees, and delete a branch only where GitHub accounts for its
# tip. Prints one tab-separated record per line and never prompts; the skill
# over it resolves the layout, decides whether to pass --act, and writes the
# prose. See plugins/kit/skills/worktree-reclaim/SKILL.md.
#
#   worktree-reclaim.sh [--repo DIR] [--target BRANCH|PATH] [--act]
#                       [--remove-cmd CMD] [--worktree-root DIR]
#   worktree-reclaim.sh [--repo DIR] --account BRANCH
#
# --worktree-root is the caller asserting that the directory holds nothing but
# worktrees it placed, and it is the only thing that licenses sweeping husks git
# no longer names. Omit it and no directory is ever listed.
#
# --account answers the branch question alone, exiting 0 only when GitHub
# accounts for the tip. It is the seam for any other caller that deletes a
# branch. Why it asks rather than infers: docs/adr/0002.
#
# Records:
#   verdict<TAB>branch<TAB>path<TAB>reclaim|reclaim-keep-branch|hold<TAB>free-reason<TAB>branch-reason
#   removed<TAB>path            held<TAB>path<TAB>reason
#   branch-deleted<TAB>branch   branch-kept<TAB>branch<TAB>reason
#   orphan<TAB>path             swept<TAB>path
#
# `set -e` is deliberately absent: half the git and gh calls here are questions
# whose answer is "no", and a non-zero exit is that answer rather than a fault.
set -uo pipefail

repo="$PWD"
target=""
act=0
remove_cmd=""
worktree_root=""
account_only=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)          repo="$2"; shift 2 ;;
    --target)        target="$2"; shift 2 ;;
    --act)           act=1; shift ;;
    --remove-cmd)    remove_cmd="$2"; shift 2 ;;
    --worktree-root) worktree_root="$2"; shift 2 ;;
    --account)       account_only="$2"; shift 2 ;;
    *) echo "worktree-reclaim: unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "$repo" || { echo "worktree-reclaim: no such directory: $repo" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "worktree-reclaim: not a git repository: $repo" >&2; exit 2; }

emit() { local IFS=$'\t'; printf '%s\n' "$*"; }

# --- inventory ----------------------------------------------------------

# One `path<TAB>branch` line per linked worktree. Porcelain terminates every
# block with a blank line, and the main worktree is always the first — never a
# candidate, so it is dropped rather than filtered by path.
inventory() {
  local path="" branch=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)          path="${line#worktree }"; branch="" ;;
      branch\ refs/heads/*) branch="${line#branch refs/heads/}" ;;
      "")                   printf '%s\t%s\n' "$path" "$branch" ;;
    esac
  done < <(git worktree list --porcelain) | tail -n +2
}

# --- freeness -----------------------------------------------------------

# True when any ancestor of the entry, up to the worktree root, is itself a
# symlink. A link created *over* a tracked directory hides the files git expects
# inside it, so git reports them deleted for the worktree's whole life. Restoring
# them is not the fix — the checkout writes through the link into the main
# checkout and the deletion comes straight back.
ancestor_is_symlink() { # worktree relpath
  local wt="$1" rel="$2" acc="" part
  local OLDIFS="$IFS"; IFS='/'
  # shellcheck disable=SC2086
  set -- $rel
  IFS="$OLDIFS"
  for part in "$@"; do
    acc="${acc:+$acc/}$part"
    [ -L "$wt/$acc" ] && return 0
  done
  return 1
}

# A lock a ship pass took is a lease rather than a permanent hold: the pass
# that took it cannot release it if it is killed, and a worktree no sweep can
# ever reclaim is a worse outcome than the race the lock exists to prevent. Only
# the kit's own reason format expires — a hand-written lock is somebody saying
# they are in there, and nothing here knows when they will be done.
KIT_LEASE_HOURS="${KIT_LEASE_HOURS:-12}"

lease_expired() { # reason -> 0 when it is a kit lease past its window
  case "$1" in "kit:ship "*" since "*) ;; *) return 1 ;; esac
  # python3 rather than `date`: the -d and -j -f spellings are GNU's and BSD's
  # respectively, and this runs on both.
  python3 - "$1" "$KIT_LEASE_HOURS" 2>/dev/null <<'LEASE'
import datetime, sys
stamp = sys.argv[1].rsplit(" since ", 1)[1].strip()
try:
    taken = datetime.datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ")
except ValueError:
    raise SystemExit(1)  # undatable: hold, rather than reclaim on a guess
taken = taken.replace(tzinfo=datetime.timezone.utc)
age = (datetime.datetime.now(datetime.timezone.utc) - taken).total_seconds()
raise SystemExit(0 if age > float(sys.argv[2]) * 3600 else 1)
LEASE
}

FREE=""; FREE_REASON=""
freeness() { # path
  local wt="$1" entry code p admin reason
  if [ ! -d "$wt" ]; then
    FREE="yes"; FREE_REASON="already gone from disk"; return
  fi
  # A lock is somebody saying they are in there, and it outranks a clean status.
  # Read from the admin file rather than `git worktree list --porcelain`, which
  # only reports it from git 2.36.
  admin="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)"
  if [ -n "$admin" ] && [ -f "$admin/locked" ]; then
    reason="$(tr -d '\n' < "$admin/locked" 2>/dev/null)"
    if lease_expired "$reason"; then
      FREE="yes"; FREE_REASON="lease expired: $reason"
    else
      FREE="no"; FREE_REASON="locked${reason:+: $reason}"
    fi
    return
  fi
  while IFS= read -r -d '' entry; do
    code="${entry:0:2}"
    p="${entry:3}"
    case "$code" in
      '??')
        # A symlink kit:start-ticket wire-worktree created back into the main
        # checkout is a setup artifact, not work. Confirm with a link test
        # rather than by matching names; the set is project-specific.
        [ -L "$wt/$p" ] && continue
        FREE="no"; FREE_REASON="uncommitted work: untracked $p"; return ;;
      ' D'|'D '|'AD')
        ancestor_is_symlink "$wt" "$p" && continue
        FREE="no"; FREE_REASON="uncommitted work: deleted $p"; return ;;
      *)
        FREE="no"; FREE_REASON="uncommitted work: ${code# } $p"; return ;;
    esac
  done < <(git -C "$wt" status --porcelain -z 2>/dev/null)
  FREE="yes"; FREE_REASON="clean"
}

# --- tip accounting -----------------------------------------------------

# Why this asks GitHub rather than inferring from a `git branch -d` refusal:
# docs/adr/0002. Every path that cannot get an answer reports unaccounted.
#
# Asks about the bare commit rather than the branch's PR: a squash-merge that
# deletes its head branch reports a headRefOid that is neither the branch's
# real tip nor present in the clone, so comparing it to the tip is a proxy the
# workflow invalidates (#98). GitHub's own commit->PR index answers the ADR's
# question directly and survives exactly that case, because it is keyed off
# the commit rather than off what a ref currently reports.
ACCOUNTED=""; ACC_REASON=""
account_branch() { # branch
  local branch="$1" tip json parsed num state
  if [ -z "$branch" ]; then
    ACCOUNTED="no"; ACC_REASON="detached HEAD, no branch to account for"; return
  fi
  tip="$(git rev-parse --verify -q "refs/heads/$branch")" || {
    ACCOUNTED="no"; ACC_REASON="no local branch $branch"; return; }

  # `gh api` writes its JSON body to stdout even on a non-2xx response, so a
  # nonzero exit needs no separate check here: any failure worth telling apart
  # from a genuine "no PR" already shows up as a body the parse below cannot
  # turn into "none" — a "404"/"422" status is the one shape that means
  # GitHub has never seen this commit; every other shape, including one `gh`
  # never got an answer for at all (empty stdout), falls to "error" below.
  json="$(gh api "repos/{owner}/{repo}/commits/$tip/pulls" 2>/dev/null)"

  # python3 rather than `gh --jq`, though gh embeds its own jq: keeping the
  # parse on this side is what lets the test suite answer with a stub `gh`
  # that only has to cat a fixture. A 404/422 error body (GitHub has never
  # seen this commit) parses as "none", the same as an empty list — both mean
  # no PR is associated with this exact commit.
  parsed="$(printf '%s' "$json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("error"); raise SystemExit
if isinstance(d, dict):
    print("none" if str(d.get("status")) in ("404", "422") else "error")
    raise SystemExit
if not d:
    print("none"); raise SystemExit
merged = [p for p in d if p.get("merged_at")]
closed = [p for p in d if p.get("state") == "closed"]
if merged:
    print("MERGED", merged[0].get("number", 0))
elif closed:
    print("CLOSED", closed[0].get("number", 0))
else:
    print("OPEN", d[0].get("number", 0))
' 2>/dev/null)"

  case "$parsed" in
    ""|error)
      ACCOUNTED="no"
      ACC_REASON="GitHub could not be asked, so tip $tip is unaccounted"
      return ;;
    none)
      # No PR is associated with this exact commit. The remaining question is
      # whether any remote ref contains the tip; nothing else can vouch for it.
      if [ -z "$(git rev-list -1 "$tip" --not --remotes 2>/dev/null)" ]; then
        ACCOUNTED="yes"; ACC_REASON="no PR, tip $tip is on a remote ref"
      else
        ACCOUNTED="no"; ACC_REASON="no PR and tip $tip is on no remote ref"
      fi
      return ;;
  esac

  read -r state num <<<"$parsed"
  case "$state" in
    MERGED|CLOSED)
      ACCOUNTED="yes"; ACC_REASON="PR #$num $state, tip $tip received" ;;
    *)
      ACCOUNTED="no"; ACC_REASON="PR #$num is $state, not a terminal state" ;;
  esac
}

if [ -n "$account_only" ]; then
  account_branch "$account_only"
  if [ "$ACCOUNTED" = "yes" ]; then
    emit accounted "$account_only" "$ACC_REASON"; exit 0
  fi
  emit unaccounted "$account_only" "$ACC_REASON"; exit 1
fi

# --- acting -------------------------------------------------------------

# `u+rwX` rather than `u+w`: a directory its writer left non-traversable cannot
# be descended into to delete what is under it, so `rm -rf` fails on the
# directory itself and leaves the husk this existed to remove. `X` adds execute
# to directories only, never to files.
sweep_dir() { # path
  chmod -R u+rwX "$1" 2>/dev/null
  rm -rf "$1"
  [ -e "$1" ] || emit swept "$1"
}

reclaim_path() { # path branch -> 0 when the path is gone
  local path="$1" branch="$2"
  # Only an expired lease reaches here still locked — a held worktree never gets
  # this far — and `git worktree remove` refuses a lock however stale it is.
  git worktree unlock "$path" >/dev/null 2>&1
  if [ -n "$remove_cmd" ]; then
    # The project's own teardown replaces `git worktree remove` rather than
    # preceding it; kit:worktree-conventions Step 3 says why.
    $remove_cmd "$branch" "$path" >/dev/null 2>&1
  else
    git worktree remove --force "$path" >/dev/null 2>&1
  fi
  # No pre-emptive chmod: it walks the whole tree on every removal, and the only
  # case that needs it is the one where the removal fails and lands here.
  [ -e "$path" ] && sweep_dir "$path"
  [ ! -e "$path" ]
}

# --- main ---------------------------------------------------------------

selected=""
while IFS=$'\t' read -r path branch; do
  [ -n "$path" ] || continue
  if [ -n "$target" ] && [ "$branch" != "$target" ] && [ "$path" != "$target" ]; then
    continue
  fi
  selected="yes"

  freeness "$path"
  if [ "$FREE" != "yes" ]; then
    # Held worktrees keep their branch whatever GitHub would have said, so the
    # round trip to ask is work nothing acts on.
    emit verdict "$branch" "$path" hold "$FREE_REASON" "not asked, worktree is held"
    [ "$act" -eq 1 ] && emit held "$path" "$FREE_REASON"
    continue
  fi

  account_branch "$branch"
  if [ "$ACCOUNTED" = "yes" ]; then
    emit verdict "$branch" "$path" reclaim "$FREE_REASON" "$ACC_REASON"
  else
    emit verdict "$branch" "$path" reclaim-keep-branch "$FREE_REASON" "$ACC_REASON"
  fi

  [ "$act" -eq 1 ] || continue

  if ! reclaim_path "$path" "$branch"; then
    emit held "$path" "could not be removed"
    continue
  fi
  emit removed "$path"

  if [ "$ACCOUNTED" = "yes" ]; then
    # -D rather than -d: the ancestry test -d applies carries no information
    # once GitHub has vouched for the tip, and refuses every squash-merge.
    git branch -D "$branch" >/dev/null 2>&1 && emit branch-deleted "$branch"
  else
    emit branch-kept "$branch" "$ACC_REASON"
  fi
done < <(inventory)

if [ -n "$target" ] && [ -z "$selected" ]; then
  echo "worktree-reclaim: no worktree matches target: $target" >&2
  exit 1
fi

# --- orphans ------------------------------------------------------------

# Husks accumulate from past runs and from manual removals: `git worktree
# remove` deletes tracked files only, and `git worktree prune` never touches a
# directory. Only --worktree-root licenses looking for them, and only inside
# itself — kit:worktree-conventions' sweep rule is what decides when a caller
# may assert one.
if [ -z "$target" ] && [ -n "$worktree_root" ] && [ -d "$worktree_root" ]; then
  live="$(git worktree list --porcelain | sed -n 's/^worktree //p')"
  for candidate in "$worktree_root"/*; do
    [ -e "$candidate" ] || continue
    resolved="$(cd "$candidate" 2>/dev/null && pwd -P)" || resolved="$candidate"
    printf '%s\n' "$live" | grep -Fxq "$resolved" && continue
    emit orphan "$candidate"
    [ "$act" -eq 1 ] && sweep_dir "$candidate"
  done
fi

[ "$act" -eq 1 ] && git worktree prune >/dev/null 2>&1

exit 0
