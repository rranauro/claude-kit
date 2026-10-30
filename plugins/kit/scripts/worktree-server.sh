#!/usr/bin/env bash
# Make the server a project declares for one worktree answer at its declared
# URL, booting it only when nothing answers there. Prints one tab-separated
# record and never prompts; kit:worktree-conventions decides whether a pass may
# boot at all. The trap is a second server: booting without asking first leaves
# two processes contending for one URL.
#
#   worktree-server.sh --server LINE --url URL --branch BRANCH --path PATH
#                      [--wait SECONDS]
#
# Records, and exit codes:
#   answering<TAB>url              0  something already answers; nothing booted
#   booted<TAB>url                 0  booted, and it answered within --wait
#   not-answering<TAB>url<TAB>log  4  booted, but nothing answered within --wait
#   not-started<TAB>reason         5  the server line did not parse or run
#   (usage on stderr)              2
#
# Any HTTP response is an answer, a 500 included: the server is up, and what it
# serves is the caller's to judge. The URL is never derived — `<branch>` and
# `<path>` are substituted into it as into the server line, and nothing else.
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/declared-call.sh"

server="" url="" branch="" path="" wait=120

while [ $# -gt 0 ]; do
  case "$1" in
    --server) server="$2"; shift 2 ;;
    --url)    url="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --path)   path="$2"; shift 2 ;;
    --wait)   wait="$2"; shift 2 ;;
    *) echo "worktree-server: unknown argument: $1" >&2; exit 2 ;;
  esac
done

for required in server url branch path; do
  [ -n "${!required}" ] || { echo "worktree-server: --$required is required" >&2; exit 2; }
done

url="$(substitute "$(substitute "$url" "<branch>" "$branch")" "<path>" "$path")"

answers() { curl -s -o /dev/null --max-time 2 "$url"; }

if answers; then
  printf 'answering\t%s\n' "$url"
  exit 0
fi

if ! declared_argv "$server" "$branch" "$path"; then
  printf 'not-started\tserver line could not be parsed: %s\n' "$server"
  exit 5
fi

# The worktree's own git directory, not its tree: a log there is never tracked,
# never shows in `git status`, and goes when the worktree does.
log="$(git -C "$path" rev-parse --absolute-git-dir 2>/dev/null)/kit-server.log"

# A new session, so the server is not in the calling shell's process group and
# outlives the pass that booted it — which is the whole point of booting it.
if ! reason="$(python3 -c '
import subprocess, sys
cwd, log, argv = sys.argv[1], sys.argv[2], sys.argv[3:]
try:
    with open(log, "ab") as out:
        subprocess.Popen(argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=out,
                         stderr=subprocess.STDOUT, start_new_session=True)
except OSError as e:
    print(e.strerror or e, end="")
    sys.exit(1)
' "$path" "$log" "${DECLARED_ARGV[@]}" 2>&1)"; then
  printf 'not-started\t%s: %s\n' "${DECLARED_ARGV[0]}" "$reason"
  exit 5
fi

deadline=$((SECONDS + wait))
while [ "$SECONDS" -lt "$deadline" ]; do
  if answers; then
    printf 'booted\t%s\n' "$url"
    exit 0
  fi
  sleep 1
done

printf 'not-answering\t%s\t%s\n' "$url" "$log"
exit 4
