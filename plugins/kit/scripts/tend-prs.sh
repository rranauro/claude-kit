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

# --- Teardown requests --------------------------------------------------------
# Removing a worktree is the other half of the problem the idle survey solved,
# and it splits the same way. `/kit:cleanup-worktree` Step 5 sweeps the husk
# `git worktree remove` leaves behind with `chmod -R u+w` and `rm -rf`, and the
# kit's grant denies `rm:*` on purpose — this is a scheduled job deleting
# directories with nobody watching, and that deny is the one entry standing
# between a bad path and an unrecoverable sweep. Granting it back to buy one
# repo its cleanup would spend the boundary for every repo the kit tends.
#
# So the agent nominates and the runner executes. The agent decides *which*
# worktrees are eligible — that needs merged-PR state and `kit-hold`, which only
# it has fetched — and writes their paths here, one per line. This runs the
# teardown afterwards in plain bash, outside the grant entirely.
#
# The asymmetry is what makes it safe: a nomination is a *name*, never a path to
# delete. It is matched against what `git worktree list` reports for this
# checkout at teardown time, so the only paths that can be swept are ones git
# already agrees are linked worktrees of this repo. A path the model composed,
# a typo, a directory outside the repo, or MAIN_CHECKOUT itself matches nothing
# and is refused.
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

# --- Prompt -------------------------------------------------------------------
# The pass itself is /kit:tend-prs. This says only what the command cannot know
# about its own invocation: that there is genuinely no terminal, and what to do
# when it runs into something it is not permitted to do.
PROMPT="Run one complete /kit:tend-prs pass over ${REPO}, from the main checkout at ${MAIN_CHECKOUT}.

Read ${COMMANDS_DIR}/tend-prs.md and follow it verbatim. Where it delegates to another /kit: command, read that command's file from the same directory and follow it the same way — /kit:review-copilot is review-copilot.md, /kit:cleanup-worktree is cleanup-worktree.md, /kit:commit is commit.md. Those files say to delegate 'via the Skill tool'; that does not work here, because the Skill tool resolves skills and these are commands. Reading the file is the delegation. Do not treat an 'Unknown skill' error as a reason to skip a step.

That directory is outside your working directory, so listing it with ls or find is denied while the Read tool reaches it fine. Do not probe for a command file — every /kit: command names an existing <name>.md there, so read the one you need directly.

Your report is captured to a log by this runner, which redirects your output into it. Print the Step 7 report and nothing more; do not try to write or append to any log file yourself.

You are running headlessly from a scheduled launchd job. There is no terminal attached and no one to prompt — the command's no-questions constraint is a fact of this environment, not an instruction you could choose to disregard.

This pass's \`idle-check\` verdicts, surveyed by the runner immediately before you started, one line per linked worktree as <path> <branch> <idle|busy> <reason>:

${IDLE_SURVEY}
Treat these as the answer to Step 3 and do not re-derive them — you are not permitted to, and the attempt is what stalls a pass. A worktree absent from this list has none; \`busy\` means skip and report the reason verbatim. The survey is a snapshot taken seconds ago, which is the same guarantee a check you ran yourself would give.

You cannot remove a worktree yourself — \`rm\` is denied to you by design, and the husk sweep in \`/kit:cleanup-worktree\` Step 5 needs it. This runner does the removal after you finish. So for Step 7 cleanup, decide eligibility as the command says — the PR is \`MERGED\`, it does not carry \`kit-hold\`, and the survey above reports the worktree \`idle\` — and then, instead of running \`/kit:cleanup-worktree\` Steps 5 through 7, append that worktree's absolute path as one line to:

${REMOVAL_REQUEST}

Nothing else goes in that file, one path per line, and only paths that appeared verbatim in the survey above. The runner re-checks each one is idle at the moment it deletes it, then stops the worktree's daemons, removes it, sweeps the husk, deletes the merged branch, and prunes. Report those worktrees as cleaned up in your Step 7 report, noting the runner performs the removal.

Steps 3 and 4 of \`/kit:cleanup-worktree\` are both already answered by the survey above — Step 3's uncommitted-work check is what the survey's \`busy\`/\`idle\` verdict *is*, applying that step's known-safe rule in full. Do not run \`git -C <worktree> status --porcelain\` to re-derive it; that call is not permitted here and attempting it is what has been stalling cleanup. Steps 1, 2, and 6 of that command still apply to you as written.

Your permissions are a fixed allowlist. If you need a tool or command outside it, the call fails: do not retry it, do not look for another way around it, and do not treat the denial as a reason to skip silently. Record what was denied and why you wanted it, then carry on with the rest of the pass — a permission boundary that turns out to be too narrow is something to widen deliberately, after reading the report.

Finish by printing the command's Step 7 report, in full, including every skip reason. It is written to a log nobody is watching in real time, so the report is the whole record of this pass."

if [ "$DRY_RUN" = "1" ]; then
  echo "repo:     ${REPO}"
  echo "checkout: ${MAIN_CHECKOUT}"
  echo "settings: ${SETTINGS}"
  echo "overlay:  ${OVERLAY_NOTE}"
  echo "log:      ${LOG}"
  echo "removals: ${REMOVAL_REQUEST}"
  echo "commands: ${COMMANDS_DIR}"
  echo "would run: ${CLAUDE_BIN} -p --model ${MODEL} --setting-sources '' --settings ${EFFECTIVE_SETTINGS} <prompt>"
  exit 0
fi

# --- Run ----------------------------------------------------------------------
log "=== pass start repo=${REPO} checkout=${MAIN_CHECKOUT} model=${MODEL} auth=subscription${AUTH_NOTE} overlay=${OVERLAY_NOTE}"

# A hung pass must not hold the lock until the next reboot. `timeout` is not on
# a stock macOS, so the watchdog is a background sleep that kills this process
# group — cheap, and it fires whether the hang is in the model or in a gh call.
( sleep "$TIMEOUT"; kill -TERM -$$ 2>/dev/null ) &
WATCHDOG=$!

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

# Run the teardown the pass nominated, whatever its exit status. A pass that
# died after verifying a merged PR and writing the nomination has still done the
# work of deciding; every path is re-validated and re-checked for idleness here,
# so acting on the file is no more trusting than acting on a clean exit.
perform_teardown

if [ "$STATUS" -eq 0 ]; then
  log "=== pass end ok"
else
  log "=== pass end FAILED (exit ${STATUS})"
  # Escalate the same way the command does. A pass that cannot run at all is
  # exactly the case the quiet-pass rule is not meant to cover.
  osascript -e "display notification \"tend-prs pass failed (exit ${STATUS}) — see ${LOG}\" with title \"Claude Code\" subtitle \"${REPO}\" sound name \"Glass\"" 2>/dev/null
fi

exit "$STATUS"
