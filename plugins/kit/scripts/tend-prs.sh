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
# interactively, so a call the grant does not cover fails the pass and gets
# reported rather than prompting. Widening it is an edit to a file you can read
# and diff.
#
# What that grant does and does not control, measured rather than assumed:
#
#   Read-only commands are auto-approved by the CLI's own classifier and cannot
#   be narrowed by an allowlist — `ls` runs whether or not it is listed, under
#   every --permission-mode. Do not read the allow list as an exhaustive
#   inventory of what a pass may execute.
#
#   Every *write* is denied unless enumerated. An unlisted side-effecting
#   command (curl, chmod, touch) is refused with "requires approval", which
#   headless means refused outright. That is the boundary that matters: what the
#   pass can change, not what it can look at.
#
#   deny beats allow, and is load-bearing rather than decorative. `git push` has
#   to be allowed for the triage step to push fixes, which would otherwise carry
#   `git push --force` in with it; the deny entry is what keeps that out, and it
#   was verified to block with the broad allow in place.
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

# A headless pass reads its commands off disk. Three things have to be true at
# once and only this arrangement gets all three:
#
#   The kit is a plugin, so /kit:tend-prs is the name it is known by — but a
#   `claude -p` does not load plugin commands the way an interactive session
#   does, and --setting-sources '' below drops `enabledPlugins` besides.
#   --plugin-dir makes the names resolve, and still does not make them
#   *invokable*: the Skill tool only resolves plugins/kit/skills/, and these
#   live in plugins/kit/commands/. Delegating "via the Skill tool", as the
#   command files say, fails with "Unknown skill" every time.
#
#   So the pass is pointed at the files. Verified working: passes told to do
#   this run the command; passes told to use the Skill tool spend a turn
#   discovering the above and then fall back to it anyway.
#
#   The path is resolved from this script, never from --repo-dir. The kit and
#   the repo being tended are different checkouts — tending ~/dev/zcommerce has
#   to read commands from wherever the kit itself lives — and deriving from
#   SCRIPT_DIR is what keeps that true for a marketplace cache too.
KIT_ROOT="$(cd "${SCRIPT_DIR}/../../.." 2>/dev/null && pwd)"
COMMANDS_DIR="${KIT_ROOT}/plugins/kit/commands"
[ -f "${COMMANDS_DIR}/tend-prs.md" ] || {
  echo "error: could not find the kit's commands from ${SCRIPT_DIR} (looked in ${COMMANDS_DIR})" >&2; exit 1; }

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

# --- Project overlay grant ----------------------------------------------------
# The kit cannot know a project's quality gates. /kit:commit discovers them from
# CLAUDE.md at runtime, so they are whatever that repo says they are — `bundle
# exec rspec`, `npm test`, a rake task — and the triage step cannot finish a pass
# without running them. Baking a guess into the kit's grant would hand every
# repo `bundle exec` to buy one repo its gates.
#
# So a project declares its own additions in .claude/tending-settings.json, and
# they are merged over the kit's here. Only `allow` can be extended: deny beats
# allow in the merged file, so a project can widen what a pass may run without
# being able to unlock anything the kit refuses. That asymmetry is the point —
# the overlay lives in a repo the pass has write access to.
OVERLAY="${MAIN_CHECKOUT}/.claude/tending-settings.json"
EFFECTIVE_SETTINGS="$SETTINGS"
OVERLAY_NOTE="none"

if [ -f "$OVERLAY" ]; then
  MERGED="$(mktemp -t tending-settings)" || { echo "error: could not create temp settings" >&2; exit 1; }
  if BASE="$SETTINGS" EXTRA="$OVERLAY" OUT="$MERGED" python3 - <<'PY'
import json, os, sys

def grant(path):
    with open(path) as f:
        return json.load(f).get("permissions", {})

try:
    base, extra = grant(os.environ["BASE"]), grant(os.environ["EXTRA"])
except (OSError, ValueError) as e:
    print(f"overlay unreadable: {e}", file=sys.stderr)
    sys.exit(1)

def union(key):
    seen, out = set(), []
    for entry in list(base.get(key, [])) + list(extra.get(key, [])):
        if entry not in seen:
            seen.add(entry)
            out.append(entry)
    return out

# Only allow/deny are merged. A project cannot set defaultMode or anything else
# that would change how the grant is interpreted rather than what it contains.
with open(os.environ["OUT"], "w") as f:
    json.dump({"permissions": {"allow": union("allow"), "deny": union("deny")}}, f, indent=2)
PY
  then
    EFFECTIVE_SETTINGS="$MERGED"
    OVERLAY_NOTE="$OVERLAY"
  else
    # A malformed overlay falls back to the kit's grant rather than failing the
    # pass. The consequence is a denial reported by the pass, which is legible;
    # the alternative is a scheduled job that stops running over a typo.
    echo "warning: ignoring unreadable overlay at ${OVERLAY}" >&2
    OVERLAY_NOTE="${OVERLAY} (ignored — unreadable)"
    rm -f "$MERGED"
  fi
fi

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

# One trap for everything that must not outlive the pass. Set here rather than
# where each thing is created, because a second `trap ... EXIT` replaces the
# first — the merged settings file above would leak on every firing.
cleanup() {
  rm -rf "$LOCK"
  [ "$EFFECTIVE_SETTINGS" != "$SETTINGS" ] && rm -f "$EFFECTIVE_SETTINGS"
  [ -n "${REMOVAL_REQUEST:-}" ] && rm -f "$REMOVAL_REQUEST"
  return 0
}
trap cleanup EXIT INT TERM

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

# --- Toolchain PATH -----------------------------------------------------------
# The plist's PATH covers gh, claude, and git; it does not cover a per-project
# language runtime. A version manager works by putting its shims ahead of the
# system binaries in a login shell's PATH, and launchd starts no login shell, so
# a pass inherits the *system* runtime instead — on macOS that is Ruby 2.6 and a
# `/usr/local/bin/bundle` shim that dies with "bad interpreter".
#
# The damage is quiet and specific: the pass still triages, still commits, still
# pushes, and only the quality gates fail — so review fixes land unverified while
# the report calls it an environment note. Prepend whatever shim directories
# exist; this runs on every firing, so an already-installed plist is fixed
# without reinstalling.
TOOLCHAIN_DIRS=""
for shim_dir in \
  "$HOME/.rbenv/shims" \
  "$HOME/.nodenv/shims" \
  "$HOME/.pyenv/shims" \
  "$HOME/.asdf/shims" \
  "$HOME/.local/share/mise/shims" \
  "$HOME/.volta/bin"
do
  [ -d "$shim_dir" ] && TOOLCHAIN_DIRS="${TOOLCHAIN_DIRS}${shim_dir}:"
done
if [ -n "$TOOLCHAIN_DIRS" ]; then
  export PATH="${TOOLCHAIN_DIRS}${PATH}"
  log "toolchain path: prepended ${TOOLCHAIN_DIRS%:}"
else
  log "toolchain path: no version-manager shims found; gates run against the system runtime"
fi

# --- Idle survey --------------------------------------------------------------
# `idle-check` asks whether a worktree is free to be written to. The agent cannot
# answer it: proving it needs `git status` and `lsof` against a path that is not
# its cwd, and every form of that is either unmatched by the grant (`git -C …`,
# `cd … && git status` — both fail the first-token rule) or unsafe to grant (a
# `Bash(cd:*)` prefix matches a compound command, so every deny entry is one `&&`
# away from being bypassed). The runner has no such problem: it is plain bash,
# outside the grant entirely. So it answers the question and passes the verdicts
# in, the same move the escalation notification already makes.
#
# Emits one line per linked worktree: "<path>\t<branch>\t<idle|busy>\t<reason>".
has_symlink_ancestor() {
  local wt="$1" rel="$2" dir
  dir="$(dirname "$rel")"
  while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    [ -L "${wt}/${dir}" ] && return 0
    dir="$(dirname "$dir")"
  done
  return 1
}

# Processes whose cwd is inside the worktree, as "<pid> <command-name>". This
# pass's own pid is never one of them.
cwd_holders() {
  lsof -d cwd 2>/dev/null | grep -F "$1" | awk -v me="$$" '$2 != me { print $2, $1 }'
}

# Cache daemons a linter starts behind your back, matched on the full command
# line rather than the process name — `ruby` is what lsof reports for a rubocop
# server, and it is equally what it reports for a spec run someone is watching.
#
# Matched as a *prefix* of the command line, never a substring: a substring
# match also hits every process that merely mentions the pattern — the grep
# looking for it, an editor with this script open, a shell whose history line
# contains it — and TERMs them. One pattern per line, each written as the
# daemon's command line actually begins.
RECLAIMABLE_DAEMONS='rubocop --server'

# A worktree is held by two unlike things. An editor or a shell is someone's
# session: it holds a cwd because a person is standing there, and removing the
# directory under them is the thing idle-check exists to prevent. A linter's
# cache daemon is nobody's session — it is started by an autoformat hook,
# reparented to init, and it idles on that cwd until the machine reboots. Left
# alone it is not a transient condition a later pass clears, which is what
# "deferred to a later pass" promises: the worktree is held forever, by a process
# whose only purpose is to make the next lint run faster.
#
# So stop them and re-ask. Stopping one costs the next lint run its warm start
# and nothing else.
reclaim_daemons() {
  local wt="$1" pid command pattern reclaimed=0
  while read -r pid _; do
    [ -z "$pid" ] && continue
    command="$(ps -p "$pid" -o command= 2>/dev/null)"
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      case "$command" in
        "$pattern"*)
          kill "$pid" 2>/dev/null || continue
          reclaimed=1
          log "reclaimed '${pattern}' (pid $pid) holding $wt"
          break
          ;;
      esac
    done <<<"$RECLAIMABLE_DAEMONS"
  done < <(cwd_holders "$wt")

  # The caller re-asks lsof straight after, and a TERM the kernel has not
  # delivered yet would still read as held — reporting busy for a process this
  # function just retired, and deferring the cleanup one more pass for nothing.
  [ "$reclaimed" -eq 1 ] && sleep 1
  return 0
}

survey_worktree() {
  local wt="$1" branch="$2" leftovers="" line code file procs
  # Known-safe leftovers, per /kit:cleanup-worktree Step 3: setup symlinks back
  # into the main checkout. They arrive in two spellings — untracked for a link
  # that adds a path, deleted for one laid *over* a tracked directory (Rails'
  # storage/ shadowing storage/.keep). Both are wiring, neither is work.
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    code="${line:0:2}"
    file="${line:3}"
    case "$code" in
      '??') [ -L "${wt}/${file}" ] && continue ;;
      *D*)  has_symlink_ancestor "$wt" "$file" && continue ;;
    esac
    leftovers="${leftovers}${leftovers:+, }${line}"
  done < <(cd "$wt" 2>/dev/null && git status --porcelain 2>/dev/null)

  if [ -n "$leftovers" ]; then
    printf '%s\t%s\tbusy\tuncommitted work: %s\n' "$wt" "$branch" "$leftovers"
    return
  fi

  # A process whose cwd sits in the worktree is usually an editor or shell
  # someone left open. Reclaim the exceptions first — see reclaim_daemons — or a
  # linter's cache daemon defers the same cleanup on every pass, forever.
  reclaim_daemons "$wt"

  # Exclude this pass's own pid so the survey never reports itself.
  procs="$(cwd_holders "$wt" | awk '{ print $2 }' | sort -u | tr '\n' ' ')"
  if [ -n "${procs// /}" ]; then
    printf '%s\t%s\tbusy\tin use by: %s\n' "$wt" "$branch" "${procs% }"
    return
  fi

  printf '%s\t%s\tidle\t-\n' "$wt" "$branch"
}

# Run *after* the merge-side cleanup, never before it. The survey is what the
# model is handed in place of a check it cannot make, and a worktree this pass
# removed a moment ago has no business appearing in it — a verdict for a path
# that no longer exists is the one kind of staleness the re-check at deletion
# cannot catch, because nothing gets deleted twice.
IDLE_SURVEY=""
run_idle_survey() {
  local wt_path wt_branch
  IDLE_SURVEY=""
  while IFS= read -r wt_path; do
    [ -z "$wt_path" ] && continue
    [ "$wt_path" = "$MAIN_CHECKOUT" ] && continue
    wt_branch="$(cd "$wt_path" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    IDLE_SURVEY="${IDLE_SURVEY}$(survey_worktree "$wt_path" "${wt_branch:-unknown}")
"
  done < <(git -C "$MAIN_CHECKOUT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')

  [ -z "$IDLE_SURVEY" ] && IDLE_SURVEY="(no linked worktrees)"
  log "idle survey: $(printf '%s' "$IDLE_SURVEY" | tr '\n' ';')"
}

# --- Teardown requests --------------------------------------------------------
# Removing a worktree is the other half of the problem the idle survey solved,
# and it splits the same way. `/kit:cleanup-worktree` Step 5 sweeps the husk
# `git worktree remove` leaves behind with `chmod -R u+w` and `rm -rf`, and the
# kit's grant denies `rm:*` on purpose — this is a scheduled job deleting
# directories with nobody watching, and that deny is the one entry standing
# between a bad path and an unrecoverable sweep. Granting it back to buy one
# repo its cleanup would spend the boundary for every repo the kit tends.
#
# It does not need one. Deciding which worktrees are eligible turned out to need
# no judgment either — a merged PR is a fact GitHub reports and `kit-hold` is a
# label read rather than weighed — so `merged_cleanup` below nominates in bash
# and this executes, both outside the grant, and the model is never involved in
# the merge side at all.
#
# Nomination stays a separate step from deletion even though both are now bash,
# because the validation is worth keeping wherever the names come from: every
# path is matched against what `git worktree list` reports for this checkout at
# teardown time, so the only directories reachable are ones git already agrees
# are linked worktrees of this repo. A malformed branch name, a path outside the
# repo, or MAIN_CHECKOUT itself matches nothing and is refused. That guard cost
# nothing to write and is the difference between a bug and an unrecoverable
# `rm -rf`.
REMOVAL_REQUEST="$(mktemp -t tend-prs-removals)" || {
  echo "error: could not create removal request file" >&2; exit 1; }

# Everything `/kit:cleanup-worktree` Steps 5-7 do, for one worktree git has
# already confirmed is its own. Ordered so a failure stops that worktree rather
# than half-finishing it: the branch delete and the husk sweep only run once the
# `worktree remove` has actually succeeded.
teardown_worktree() {
  local wt="$1" branch="$2"

  # Per-directory daemons bound to this path. reclaim_daemons already stopped
  # the ones the survey recognizes, but the pass ran for minutes since — an
  # autoformat hook during triage restarts a rubocop server on the very
  # worktree about to be removed.
  reclaim_daemons "$wt"

  if ! git -C "$MAIN_CHECKOUT" worktree remove --force "$wt" 2>/dev/null; then
    log "teardown: FAILED to remove worktree ${wt} — left in place"
    return 1
  fi

  # `git worktree remove` deregisters git's bookkeeping and routinely leaves
  # runtime files written while the app was booted here — bootsnap caches, logs,
  # uploads — some read-only because their writer made them so. Without the
  # chmod the rm partially fails and leaves an orphan directory that VS Code and
  # Finder still show. Both are no-ops when the path is already gone.
  if [ -d "$wt" ]; then
    chmod -R u+w "$wt" 2>/dev/null
    rm -rf "$wt" 2>/dev/null
  fi
  [ -d "$wt" ] && log "teardown: husk remains at ${wt} after sweep"

  # Safe delete first. A squash-merge leaves the branch's commits out of main's
  # ancestry, so git refuses -d on work that is genuinely merged; the agent only
  # nominates worktrees whose PR it verified MERGED, which is what makes -D the
  # right escalation rather than a guess.
  if [ -n "$branch" ] && [ "$branch" != "unknown" ]; then
    if git -C "$MAIN_CHECKOUT" branch -d "$branch" 2>/dev/null; then
      log "teardown: removed ${wt} and deleted branch ${branch}"
    elif git -C "$MAIN_CHECKOUT" branch -D "$branch" 2>/dev/null; then
      log "teardown: removed ${wt} and force-deleted squash-merged branch ${branch}"
    else
      log "teardown: removed ${wt}; branch ${branch} could not be deleted"
    fi
  else
    log "teardown: removed ${wt} (no branch resolved)"
  fi
  return 0
}

perform_teardown() {
  local path branch verdict registered removed=0 refused=0

  [ -s "$REMOVAL_REQUEST" ] || { log "teardown: no worktrees nominated"; return 0; }

  registered="$(git -C "$MAIN_CHECKOUT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')"

  while IFS= read -r path; do
    path="${path#"${path%%[![:space:]]*}"}"
    path="${path%"${path##*[![:space:]]}"}"
    [ -z "$path" ] && continue
    case "$path" in '#'*) continue ;; esac

    if [ "$path" = "$MAIN_CHECKOUT" ] || ! printf '%s\n' "$registered" | grep -qxF "$path"; then
      log "teardown: REFUSED ${path} — not a linked worktree of ${REPO}"
      refused=$((refused + 1))
      continue
    fi

    # The survey that cleared this worktree was taken before the pass, and the
    # pass may have run for twenty minutes. Someone opening a shell in it since
    # then is exactly what idle-check exists to catch, so ask again at the
    # moment of deletion rather than trusting a verdict that has gone stale.
    branch="$(cd "$path" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    verdict="$(survey_worktree "$path" "${branch:-unknown}" | cut -f3-)"
    case "$verdict" in
      idle*) ;;
      *) log "teardown: skipped ${path} — became busy since the survey (${verdict#*	})"
         refused=$((refused + 1)); continue ;;
    esac

    teardown_worktree "$path" "${branch:-unknown}" && removed=$((removed + 1))
  done < "$REMOVAL_REQUEST"

  if [ "$removed" -gt 0 ]; then
    git -C "$MAIN_CHECKOUT" worktree prune 2>/dev/null
    # Remote-tracking refs for branches GitHub deleted on merge. Step 7 of
    # cleanup-worktree; it needs no worktree of its own, but it is pointless to
    # run when nothing was actually removed.
    git -C "$MAIN_CHECKOUT" remote prune origin 2>/dev/null
  fi
  log "teardown: ${removed} removed, ${refused} refused/skipped"
  return 0
}

# --- Merge-side lifecycle (no model) ------------------------------------------
# The pass has two halves and only one of them needs judgment. Verifying a
# review finding against the code is the model's work. The merge side is not:
# a merged PR is a fact GitHub reports, a worktree either matches its branch or
# does not, `kit-hold` is a label read rather than weighed, and fast-forwarding
# main is the same command every firing. Spawning a whole context to discover
# that is what made roughly two thirds of these passes cost a model to report
# they had nothing to do.
#
# So this half runs in bash on every firing, whether or not a model is started.

# Path of the linked worktree checked out on a branch, empty if none is.
worktree_for_branch() {
  git -C "$MAIN_CHECKOUT" worktree list --porcelain 2>/dev/null | awk -v want="refs/heads/$1" '
    /^worktree /{ path = $2 }
    /^branch /  { if ($2 == want) { print path; exit } }'
}

# `/kit:cleanup-worktree` Step 6's first half, and the standing request that main
# actually carry the merges this pass just cleaned up after.
#
# Every guard here is about not being the thing that loses work: it touches main
# only when main is what is checked out, only when nothing is uncommitted, and
# only when the move is a genuine fast-forward. Anything else is logged and left,
# because a scheduled job resolving a divergence unattended is how you find out
# it did the wrong one.
main_sync() {
  local branch head
  git -C "$MAIN_CHECKOUT" fetch origin main --quiet 2>/dev/null

  branch="$(git -C "$MAIN_CHECKOUT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [ "$branch" != "main" ]; then
    log "main sync: skipped — main checkout is on '${branch:-unknown}', not main"
    return 0
  fi
  if [ -n "$(git -C "$MAIN_CHECKOUT" status --porcelain 2>/dev/null)" ]; then
    log "main sync: skipped — main checkout has uncommitted changes"
    return 0
  fi
  if ! git -C "$MAIN_CHECKOUT" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
    log "main sync: local main holds commits origin/main does not; left alone"
    return 0
  fi
  if git -C "$MAIN_CHECKOUT" diff --quiet HEAD origin/main 2>/dev/null; then
    log "main sync: already current"
    return 0
  fi
  if git -C "$MAIN_CHECKOUT" merge --ff-only origin/main --quiet 2>/dev/null; then
    head="$(git -C "$MAIN_CHECKOUT" rev-parse --short HEAD 2>/dev/null)"
    log "main sync: fast-forwarded main to ${head}"
  else
    log "main sync: fast-forward refused; left alone"
  fi
}

# Step 6. Nominates the worktree of every merged PR that is not held, then hands
# the list to the teardown that already validates and re-checks each one.
#
# A merged PR still carrying `kit-hold` keeps its worktree — merging does not
# retire the hold, and that is the case the override exists for: a verification
# walk that outlives the merge still needs the worktree it is walking in.
merged_cleanup() {
  local line state num branch path nominated=0

  while IFS=$'\t' read -r state num branch; do
    [ -z "$branch" ] && continue
    path="$(worktree_for_branch "$branch")"
    [ -z "$path" ] && continue

    if [ "$state" = "held" ]; then
      log "cleanup: PR #${num} (${branch}) merged but held by kit-hold; worktree kept"
      continue
    fi
    printf '%s\n' "$path" >>"$REMOVAL_REQUEST"
    log "cleanup: nominated ${path} (PR #${num}, ${branch}, merged)"
    nominated=$((nominated + 1))
  done < <(gh pr list --author @me --state merged --limit 30 \
             --json number,headRefName,labels \
             --jq '.[] | [((.labels // []) | map(.name) | if index("kit-hold") then "held" else "free" end), (.number|tostring), .headRefName] | @tsv' \
           2>/dev/null)

  [ "$nominated" -eq 0 ] && log "cleanup: no merged-PR worktrees to remove"
  return 0
}

# --- The gate -----------------------------------------------------------------
# Whether this firing needs a model at all.
#
# This deliberately does **not** re-implement `classify`. It answers the cheaper
# question — "could there possibly be model work here?" — and errs toward yes.
# Every rule that decides what actually happens to a PR stays in tend-prs.md,
# in one place, where it is documented and can be reasoned about; duplicating it
# here in jq would give it a second home that drifts from the first, and the
# failure mode of that drift is a PR silently never triaged.
#
# So the gate is an over-approximation on purpose. A false yes costs one pass
# that reports nothing happened, which is what every pass costs today. A false
# no would strand a PR, so nothing here may be clever.
#
# The three triggers, per the command's own steps:
#
#   reviews landed, no marker  → Step 4 has triage to do
#   a failing check, unescalated → Step 5 has one escalation to record, once
#   marker present, auto-merge off → Step 5's stranding case
#
# Escalated PRs are excluded throughout: the whole point of the marker is that a
# human was asked for, so re-spawning a model to re-reach that verdict every ten
# minutes is the loop this gate exists to stop. That bound is what makes the
# failing-check trigger affordable — it fires once per red PR, not once per
# firing, because the marker it writes is durable.
GATE_REASONS=""

needs_model() {
  local num branch draft age amr labels markers escalated copilot_inline copilot_review claude_review failing

  while IFS=$'\t' read -r num branch draft age amr labels; do
    [ -z "$num" ] && continue
    [ "$draft" = "true" ] && continue
    case ",${labels}," in *,kit-hold,*) continue ;; esac

    # One read answers both "is there a marker" and "does it escalate", which is
    # why the bodies are taken rather than a count.
    markers="$(gh api "repos/${REPO}/issues/${num}/comments" \
      --jq '[.[] | select(.body | startswith("<!-- kit-triaged -->")) | .body] | join("\n")' 2>/dev/null)"
    case "$markers" in *'<!-- kit-escalated'*) continue ;; esac

    if [ -n "$markers" ]; then
      # Triaged. The only remaining question is whether it is actually on its way
      # to merging; `null` here is the stranding Step 5 describes.
      if [ "$amr" = "null" ] || [ -z "$amr" ]; then
        GATE_REASONS="${GATE_REASONS}  PR #${num} (${branch}): triaged but auto-merge is off
"
      fi
      continue
    fi

    # No marker. Has the review round landed? Logins are matched
    # case-insensitively because Copilot's inline comments come from `Copilot`
    # and its top-level review from `copilot-pull-request-reviewer[bot]`;
    # without the "i" the inline pass silently finds nothing.
    copilot_inline="$(gh api "repos/${REPO}/pulls/${num}/comments" \
      --jq '[.[] | select(.user.login | test("copilot|github-actions"; "i"))] | length' 2>/dev/null)"
    copilot_review="$(gh api "repos/${REPO}/pulls/${num}/reviews" \
      --jq '[.[] | select(.user.login | test("copilot|github-actions"; "i"))] | length' 2>/dev/null)"
    claude_review="$(gh api "repos/${REPO}/issues/${num}/comments" \
      --jq '[.[] | select(.body | startswith("<!-- claude-pr-review -->"))] | length' 2>/dev/null)"

    local has_copilot=0 has_claude=0
    [ "${copilot_inline:-0}" -gt 0 ] 2>/dev/null && has_copilot=1
    [ "${copilot_review:-0}" -gt 0 ] 2>/dev/null && has_copilot=1
    [ "${claude_review:-0}" -gt 0 ] 2>/dev/null && has_claude=1

    # Both, or — past 30 minutes — whichever one is ever going to arrive. The
    # age escape is what stops a hook that failed to fire from stranding the PR.
    if [ "$has_copilot" = "1" ] && [ "$has_claude" = "1" ]; then
      GATE_REASONS="${GATE_REASONS}  PR #${num} (${branch}): both reviews landed, not yet triaged
"
    elif [ "${age:-0}" -ge 30 ] 2>/dev/null && { [ "$has_copilot" = "1" ] || [ "$has_claude" = "1" ]; }; then
      GATE_REASONS="${GATE_REASONS}  PR #${num} (${branch}): one review landed ${age}m ago, not yet triaged
"
    fi

    # A red check is worth one escalation, and the marker check above means it
    # is worth exactly one.
    failing="$(gh pr view "$num" --json statusCheckRollup \
      --jq '[(.statusCheckRollup // [])[] | select((.conclusion // .state) as $c | $c == "FAILURE" or $c == "ERROR" or $c == "TIMED_OUT")] | length' 2>/dev/null)"
    if [ "${failing:-0}" -gt 0 ] 2>/dev/null; then
      GATE_REASONS="${GATE_REASONS}  PR #${num} (${branch}): ${failing} failing check(s), not yet escalated
"
    fi
  done < <(gh pr list --author @me --state open --limit 50 \
             --json number,headRefName,isDraft,createdAt,labels,autoMergeRequest \
             --jq '.[] | [(.number|tostring), .headRefName, (.isDraft|tostring),
                          (((now - (.createdAt|fromdateiso8601)) / 60) | floor | tostring),
                          (if .autoMergeRequest == null then "null" else "set" end),
                          ((.labels // []) | map(.name) | join(","))] | @tsv' \
           2>/dev/null)

  [ -n "$GATE_REASONS" ]
}
# --- Dry run ------------------------------------------------------------------
# Evaluated before anything is written, so --dry-run can be used to ask "would
# this firing have started a model, and why" without syncing, deleting, or
# spawning anything.
if [ "$DRY_RUN" = "1" ]; then
  echo "repo:     ${REPO}"
  echo "checkout: ${MAIN_CHECKOUT}"
  echo "settings: ${SETTINGS}"
  echo "overlay:  ${OVERLAY_NOTE}"
  echo "log:      ${LOG}"
  echo "commands: ${COMMANDS_DIR}"
  if needs_model; then
    echo "gate:     MODEL NEEDED"
    printf '%s' "$GATE_REASONS"
    echo "would run: ${CLAUDE_BIN} -p --model ${MODEL} --setting-sources '' --settings ${EFFECTIVE_SETTINGS} <prompt>"
  else
    echo "gate:     no model needed — merge-side work only, would run in bash and exit"
  fi
  exit 0
fi

# --- Run ----------------------------------------------------------------------
log "=== pass start repo=${REPO} checkout=${MAIN_CHECKOUT} auth=subscription${AUTH_NOTE} overlay=${OVERLAY_NOTE}"

# A hung pass must not hold the lock until the next reboot. `timeout` is not on
# a stock macOS, so the watchdog is a background sleep that kills this process
# group — cheap, and it fires whether the hang is in the model or in a gh call.
# Armed before the bash phases, not just the model: a `gh` call can hang too.
( sleep "$TIMEOUT"; kill -TERM -$$ 2>/dev/null ) &
WATCHDOG=$!

# --- Phase 1: the merge side, in bash -----------------------------------------
# Runs on every firing whether or not a model is started. Ordered by dependency:
# main has to carry the merges before a branch delete can tell a merged branch
# from an unmerged one, and the survey has to describe the worktrees that are
# still there after the cleanup rather than the ones that were there before it.
main_sync
merged_cleanup
perform_teardown
run_idle_survey

# --- Phase 2: the gate --------------------------------------------------------
# The only reason left to spend a model. Everything above was mechanical; what
# remains — verifying a review finding against the code, judging whether a
# skipped item is non-minor — is not.
if ! needs_model; then
  log "=== pass end ok (no model needed)"
  kill "$WATCHDOG" 2>/dev/null
  exit 0
fi

log "model needed:$(printf '\n%s' "$GATE_REASONS" | tr '\n' ';')"

# --- Phase 3: the model -------------------------------------------------------
# The pass itself is /kit:tend-prs. This says only what the command cannot know
# about its own invocation: that there is genuinely no terminal, which of its
# steps the runner has already carried out, and what to do when it runs into
# something it is not permitted to do.
PROMPT="Run one /kit:tend-prs pass over ${REPO}, from the main checkout at ${MAIN_CHECKOUT}.

Read ${COMMANDS_DIR}/tend-prs.md and follow it verbatim, with the exception of the steps named below as already done. Where it delegates to another /kit: command, read that command's file from the same directory and follow it the same way — /kit:review-copilot is review-copilot.md, /kit:commit is commit.md. Those files say to delegate 'via the Skill tool'; that does not work here, because the Skill tool resolves skills and these are commands. Reading the file is the delegation. Do not treat an 'Unknown skill' error as a reason to skip a step.

That directory is outside your working directory, so listing it with ls or find is denied while the Read tool reaches it fine. Do not probe for a command file — every /kit: command names an existing <name>.md there, so read the one you need directly.

You are running headlessly from a scheduled launchd job. There is no terminal attached and no one to prompt — the command's no-questions constraint is a fact of this environment, not an instruction you could choose to disregard.

**This runner already did the merge side of the pass in plain bash, before starting you.** It is not yours to redo, and you have neither the permissions nor the evidence to redo it correctly:

- Step 6 \`cleanup\` is **done**. Merged PRs were matched to worktrees, anything carrying \`kit-hold\` was left alone, and the rest were removed along with their branches. Do not query merged PRs, do not nominate anything for removal, and do not report worktree cleanup — the runner logs that itself. Report only what you did.
- The \`main\` sync is **done** — main was fetched and fast-forwarded where that was safe.
- Step 3 \`idle-check\` is **answered**, below.

What is left for you is Steps 1, 2, 4, 5 and 7 — take the inventory, classify each open PR, triage the review rounds, apply the merge policy, and report.

You were started because the gate below found work that needs judgment. These are the PRs that tripped it, as the runner saw them seconds ago:

${GATE_REASONS}
Treat that as a reason you were woken, not as your classification. Derive each PR's state yourself per Step 2 — the gate deliberately over-approximates, so a PR listed here may turn out to need nothing, and that is a fine outcome to report. Do not skip a PR merely because it is absent from the list.

This pass's \`idle-check\` verdicts, surveyed by the runner after the cleanup above and immediately before you started, one line per surviving linked worktree as <path> <branch> <idle|busy> <reason>:

${IDLE_SURVEY}
Treat these as the answer to Step 3 and do not re-derive them — you are not permitted to, and the attempt is what stalls a pass. A worktree absent from this list has none; \`busy\` means skip and report the reason verbatim. In particular do not run \`git -C <worktree> status --porcelain\`: that call is denied here, and the \`uncommitted work:\` reason in a \`busy\` verdict is already that check's answer.

Your report is captured to a log by this runner, which redirects your output into it. Print the Step 7 report and nothing more; do not try to write or append to any log file yourself.

Your permissions are a fixed allowlist. If you need a tool or command outside it, the call fails: do not retry it, do not look for another way around it, and do not treat the denial as a reason to skip silently. Record what was denied and why you wanted it, then carry on with the rest of the pass — a permission boundary that turns out to be too narrow is something to widen deliberately, after reading the report.

Finish by printing the command's Step 7 report, in full, including every skip reason. It is written to a log nobody is watching in real time, so the report is the whole record of this pass."

# --setting-sources '' loads no user, project, or local settings, so the grant
# is exactly this file. Without it the pass inherits ~/.claude/settings.json and
# whatever the checkout happens to carry — today that only leaks read
# permissions, but it means the boundary drifts with a machine's global config
# rather than with a diff to the file next to this script. A scheduled job that
# nobody watches should not widen quietly because an unrelated allow rule was
# added months later.
"$CLAUDE_BIN" -p \
  --model "$MODEL" \
  --setting-sources '' \
  --settings "$EFFECTIVE_SETTINGS" \
  "$PROMPT" >>"$LOG" 2>&1 </dev/null
STATUS=$?

kill "$WATCHDOG" 2>/dev/null

if [ "$STATUS" -eq 0 ]; then
  log "=== pass end ok (model ran on ${MODEL})"
else
  log "=== pass end FAILED (exit ${STATUS})"
  # Escalate the same way the command does. A pass that cannot run at all is
  # exactly the case the quiet-pass rule is not meant to cover.
  osascript -e "display notification \"tend-prs pass failed (exit ${STATUS}) — see ${LOG}\" with title \"Claude Code\" subtitle \"${REPO}\" sound name \"Glass\"" 2>/dev/null
fi

exit "$STATUS"
