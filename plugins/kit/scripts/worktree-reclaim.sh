#!/usr/bin/env bash
# Reclaim git worktrees, and delete a branch only where GitHub accounts for its
# tip. Prints one tab-separated record per line and never prompts; the skill
# over it resolves the layout, decides whether to pass --act, and writes the
# prose. See plugins/kit/skills/worktree-reclaim/SKILL.md.
#
#   worktree-reclaim.sh [--repo DIR] [--target BRANCH|PATH] [--act]
#                       [--layout owned|project] [--remove-cmd CMD]
#                       [--worktree-root DIR]
#   worktree-reclaim.sh [--repo DIR] --account BRANCH
#
# --account answers the branch question alone and exits 0 only when GitHub
# accounts for the tip. It is the seam for any other caller that deletes a
# branch, so there is one implementation of the test rather than a copy per
# caller — which is the shape that produced the defect in the first place.
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
layout="owned"
remove_cmd=""
worktree_root=""
account_only=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)          repo="$2"; shift 2 ;;
    --target)        target="$2"; shift 2 ;;
    --act)           act=1; shift ;;
    --layout)        layout="$2"; shift 2 ;;
    --remove-cmd)    remove_cmd="$2"; shift 2 ;;
    --worktree-root) worktree_root="$2"; shift 2 ;;
    --account)       account_only="$2"; shift 2 ;;
    *) echo "worktree-reclaim: unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "$repo" || { echo "worktree-reclaim: no such directory: $repo" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "worktree-reclaim: not a git repository: $repo" >&2; exit 2; }

emit() { printf '%s\n' "$(IFS=$'\t'; echo "$*")"; }

TAB=$'\t'

# --- inventory ----------------------------------------------------------

# One `path<TAB>branch<TAB>locked-reason` line per worktree, main excluded. The
# main worktree is the first block git prints, and it is never a candidate.
inventory() {
  local path="" branch="" locked="" first=1
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        if [ -n "$path" ] && [ "$first" -eq 0 ]; then
          printf '%s\t%s\t%s\n' "$path" "$branch" "$locked"
        fi
        [ -n "$path" ] && first=0
        path="${line#worktree }"; branch=""; locked=""
        ;;
      branch\ refs/heads/*) branch="${line#branch refs/heads/}" ;;
      locked)               locked="locked" ;;
      locked\ *)            locked="locked: ${line#locked }" ;;
    esac
  done < <(git worktree list --porcelain)
  if [ -n "$path" ] && [ "$first" -eq 0 ]; then
    printf '%s\t%s\t%s\n' "$path" "$branch" "$locked"
  fi
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

FREE=""; FREE_REASON=""
freeness() { # path locked
  local wt="$1" locked="$2" entry code p admin reason
  if [ ! -d "$wt" ]; then
    FREE="yes"; FREE_REASON="already gone from disk"; return
  fi
  # `git worktree list --porcelain` only reports the lock from git 2.36, so the
  # admin file is what actually answers this on an older client. A lock is
  # somebody saying they are in there, and it outranks a clean status.
  if [ -z "$locked" ]; then
    admin="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)"
    if [ -n "$admin" ] && [ -f "$admin/locked" ]; then
      reason="$(tr -d '\n' < "$admin/locked" 2>/dev/null)"
      locked="locked${reason:+: $reason}"
    fi
  fi
  if [ -n "$locked" ]; then
    FREE="no"; FREE_REASON="$locked"; return
  fi
  while IFS= read -r -d '' entry; do
    [ -n "$entry" ] || continue
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

# The whole point of the ticket. A `git branch -d` refusal has two causes that
# are identical locally — a squash-merge, whose originals are unreachable from
# every remote ref because squashing made a new commit, and work that was
# committed and never pushed. Only the side that received the push separates
# them, so this asks rather than infers, and every path that cannot get an
# answer reports the branch as unaccounted.
ACCOUNTED=""; ACC_REASON=""
account_branch() { # branch
  local branch="$1" tip json parsed num state oid
  if [ -z "$branch" ]; then
    ACCOUNTED="no"; ACC_REASON="detached HEAD, no branch to account for"; return
  fi
  tip="$(git rev-parse --verify -q "refs/heads/$branch")" || {
    ACCOUNTED="no"; ACC_REASON="no local branch $branch"; return; }

  if ! json="$(gh pr list --head "$branch" --state all \
                 --json number,state,headRefOid --limit 1 2>/dev/null)"; then
    ACCOUNTED="no"
    ACC_REASON="GitHub could not be asked, so tip $tip is unaccounted"
    return
  fi

  # python3 over jq: it ships on macOS and every GitHub runner, jq does not.
  parsed="$(printf '%s' "$json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("error"); raise SystemExit
if not d:
    print("none")
else:
    p = d[0]
    print(p.get("number", 0), p.get("state", ""), p.get("headRefOid", ""))
' 2>/dev/null)"

  case "$parsed" in
    ""|error)
      ACCOUNTED="no"
      ACC_REASON="GitHub's answer could not be read, so tip $tip is unaccounted"
      return ;;
    none)
      # No PR ever. The remaining question is whether any remote ref contains
      # the tip; nothing else can vouch for it.
      if [ -z "$(git rev-list -1 "$tip" --not --remotes 2>/dev/null)" ]; then
        ACCOUNTED="yes"; ACC_REASON="no PR, tip $tip is on a remote ref"
      else
        ACCOUNTED="no"; ACC_REASON="no PR and tip $tip is on no remote ref"
      fi
      return ;;
  esac

  read -r num state oid <<<"$parsed"
  case "$state" in
    MERGED|CLOSED)
      if [ "$oid" = "$tip" ]; then
        ACCOUNTED="yes"; ACC_REASON="PR #$num $state received tip $tip"
      else
        ACCOUNTED="no"
        ACC_REASON="PR #$num $state at $oid; local tip $tip is ahead of it"
      fi ;;
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

# chmod before the remove, not only after it. A cache directory its writer left
# non-traversable cannot be descended into to delete what is under it, so both
# `git worktree remove` and a bare `rm -rf` fail on the directory itself and
# leave the husk this existed to remove. `u+rwX` adds execute to directories
# only, never to files.
reclaim_path() { # path -> 0 when the path is gone
  local path="$1"
  chmod -R u+rwX "$path" 2>/dev/null
  if [ -n "$remove_cmd" ]; then
    # The project's own teardown does things a raw `git worktree remove` cannot
    # reconstruct — proxy links, registered subdomains, generated config — so it
    # replaces that call rather than preceding it.
    $remove_cmd "$RECLAIM_BRANCH" "$path" >/dev/null 2>&1
  else
    git worktree remove --force "$path" >/dev/null 2>&1
  fi
  if [ -e "$path" ]; then
    chmod -R u+rwX "$path" 2>/dev/null
    rm -rf "$path"
    [ -e "$path" ] || emit swept "$path"
  fi
  [ ! -e "$path" ]
}

# --- main ---------------------------------------------------------------

selected=""
while IFS="$TAB" read -r path branch locked; do
  [ -n "$path" ] || continue
  if [ -n "$target" ] && [ "$branch" != "$target" ] && [ "$path" != "$target" ]; then
    continue
  fi
  selected="yes"

  freeness "$path" "$locked"
  free="$FREE"; free_reason="$FREE_REASON"
  account_branch "$branch"
  accounted="$ACCOUNTED"; acc_reason="$ACC_REASON"

  if [ "$free" != "yes" ]; then
    verdict="hold"
  elif [ "$accounted" = "yes" ]; then
    verdict="reclaim"
  else
    verdict="reclaim-keep-branch"
  fi

  emit verdict "$branch" "$path" "$verdict" "$free_reason" "$acc_reason"

  [ "$act" -eq 1 ] || continue

  if [ "$verdict" = "hold" ]; then
    emit held "$path" "$free_reason"
    continue
  fi

  RECLAIM_BRANCH="$branch"
  if reclaim_path "$path"; then
    emit removed "$path"
  else
    emit held "$path" "could not be removed"
    continue
  fi

  if [ "$accounted" = "yes" ]; then
    # -D rather than -d: the ancestry test -d applies carries no information
    # once GitHub has vouched for the tip, and refuses every squash-merge.
    git branch -D "$branch" >/dev/null 2>&1 && emit branch-deleted "$branch"
  else
    emit branch-kept "$branch" "$acc_reason"
  fi
done < <(inventory)

if [ -n "$target" ] && [ -z "$selected" ]; then
  echo "worktree-reclaim: no worktree matches target: $target" >&2
  exit 1
fi

# --- orphans ------------------------------------------------------------

# Husks accumulate from past runs and from manual removals: `git worktree
# remove` deletes tracked files only, and `git worktree prune` never touches a
# directory.
#
# What makes deleting one safe depends entirely on who chose the layout, and the
# two cases are not interchangeable. A project layout is frequently a sibling of
# the main checkout, which puts worktrees in the same parent as unrelated
# repositories — so a directory there that git does not name is not garbage, it
# is somebody else's. Only the fallback layout licenses a directory diff, and
# only inside its own root.
if [ -z "$target" ] && [ "$layout" = "owned" ] && [ -n "$worktree_root" ] && [ -d "$worktree_root" ]; then
  live="$(git worktree list --porcelain | sed -n 's/^worktree //p')"
  for candidate in "$worktree_root"/*; do
    [ -e "$candidate" ] || continue
    resolved="$(cd "$candidate" 2>/dev/null && pwd -P)" || resolved="$candidate"
    printf '%s\n' "$live" | grep -Fxq "$resolved" && continue
    printf '%s\n' "$live" | grep -Fxq "$candidate" && continue
    emit orphan "$candidate"
    [ "$act" -eq 1 ] || continue
    chmod -R u+rwX "$candidate" 2>/dev/null
    rm -rf "$candidate"
    [ -e "$candidate" ] || emit swept "$candidate"
  done
fi

[ "$act" -eq 1 ] && git worktree prune >/dev/null 2>&1

exit 0
