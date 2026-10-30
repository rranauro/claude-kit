# How a command a project declares in `## Worktrees` is called. Sourced, never
# run: worktree-reclaim.sh calls `remove` and worktree-server.sh calls `server`,
# and a tokeniser spelled twice lets one line mean two different calls.
#
# The declared line is the call, so the documented example and what runs are the
# same text. Tokenised with shell quoting but never evaluated, so `--reason
# "finished work"` stays one argument without the declaration becoming code.

# Not `${word//<path>/$path}`: bash 5.2 expands `&` in that replacement, and
# 3.2 keeps the quotes that would stop it.
substitute() { # text placeholder value
  local text="$1" out=""
  while [[ "$text" == *"$2"* ]]; do
    out="$out${text%%"$2"*}$3"
    text="${text#*"$2"}"
  done
  printf '%s' "$out$text"
}

declared_text() { # text branch path
  substitute "$(substitute "$1" "<branch>" "$2")" "<path>" "$3"
}

declared_argv() { # line branch path -> DECLARED_ARGV; 1 when the line does not parse
  local line="$1" branch="$2" path="$3" word
  DECLARED_ARGV=()
  while IFS= read -r -d '' word; do
    DECLARED_ARGV+=("$(declared_text "$word" "$branch" "$path")")
  done < <(python3 -c '
import shlex, sys
try:
    words = shlex.split(sys.argv[1])
except ValueError:
    sys.exit(1)
sys.stdout.write("".join(w + "\0" for w in words))
' "$line")
  [ "${#DECLARED_ARGV[@]}" -gt 0 ]
}
