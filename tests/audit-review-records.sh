#!/usr/bin/env bash
set -uo pipefail

# The audit exists because the state it looks for is invisible by construction:
# the surviving mark is the one that tells every reader to look no further. So
# the cases below are mostly about the two answers not being confusable — a PR
# whose record is present must never be named, and one whose record is absent
# must be, with an exit status a gate can branch on.
#
# `gh` is stubbed on PATH, because the question is which PRs the script pairs
# with which comment fetch, not what GitHub returns.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/plugins/kit/scripts/audit-review-records.sh"
ORIG_PATH="$PATH"

passed=0
failed=0
current=""

# --- assertions ---------------------------------------------------------

ok()  { echo "  ok   $current — $1"; passed=$((passed + 1)); }
bad() { echo "  FAIL $current — $1" >&2; failed=$((failed + 1)); }

assert_has() { # haystack needle label
  case "$1" in
    *"$2"*) ok "$3" ;;
    *)      bad "$3"; printf '       expected to find: %s\n' "$2" >&2
            printf '       in:\n%s\n' "$1" | sed 's/^/         /' >&2 ;;
  esac
}

assert_lacks() { # haystack needle label
  case "$1" in
    *"$2"*) bad "$3"; printf '       expected NOT to find: %s\n' "$2" >&2
            printf '       in:\n%s\n' "$1" | sed 's/^/         /' >&2 ;;
    *)      ok "$3" ;;
  esac
}

assert_status() { # actual expected label
  if [ "$1" = "$2" ]; then ok "$3"
  else bad "$3"; printf '       exit status %s, expected %s\n' "$1" "$2" >&2; fi
}

# --- sandbox ------------------------------------------------------------

new_sandbox() {
  current="$1"
  echo "==> $current"
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  GH_FIXTURES="$SANDBOX/fixtures"
  mkdir -p "$GH_FIXTURES" "$SANDBOX/bin"

  # `pr list` answers from one fixture holding the PR numbers `--jq` would have
  # left on stdout. The comments endpoint answers per PR, from `record.<n>` —
  # present means that PR has its marker comment, absent means it does not.
  # Which file the stub reads is the whole assertion: a script that fetched
  # comments for the wrong PR would pass every output check and still be wrong.
  cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
if [ "$1" = "repo" ]; then echo "owner/repo"; exit 0; fi
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  printf '%s\n' "$*" >> "$GH_FIXTURES/listed"
  [ -f "$GH_FIXTURES/list_fails" ] && { echo "gh: could not list" >&2; exit 1; }
  cat "$GH_FIXTURES/prs" 2>/dev/null
  exit 0
fi
if [ "$1" = "api" ]; then
  for arg in "$@"; do
    case "$arg" in
      */issues/*/comments)
        n="${arg#*/issues/}"; n="${n%/comments}"
        printf '%s\n' "$n" >> "$GH_FIXTURES/fetched"
        if [ -f "$GH_FIXTURES/record.$n" ]; then echo 1; else echo 0; fi
        exit 0 ;;
    esac
  done
  exit 0
fi
exit 0
GH
  chmod +x "$SANDBOX/bin/gh"
  export GH_FIXTURES
  export PATH="$SANDBOX/bin:$ORIG_PATH"
}

end_sandbox() {
  PATH="$ORIG_PATH"
  rm -rf "$SANDBOX"
}

# --- fixtures -----------------------------------------------------------

# The PR numbers `gh pr list --label kit-review-closed --jq` leaves on stdout.
labelled()   { printf '%s\n' "$@" > "$GH_FIXTURES/prs"; }
# Those of them whose marker comment is actually on the PR.
has_record() { for n in "$@"; do touch "$GH_FIXTURES/record.$n"; done; }

run() {
  OUT="$("$SCRIPT" "$@" 2>&1)"
  STATUS=$?
}

# --- cases --------------------------------------------------------------

new_sandbox "every labelled PR carries its record"
labelled 11 12
has_record 11 12
run
assert_status "$STATUS" 0            "exits clean"
assert_lacks "$OUT" "#11"            "names no PR"
assert_lacks "$OUT" "#12"            "names no PR"
assert_has "$OUT" "2"                "reports how many it checked"
end_sandbox

new_sandbox "a labelled PR with no record is named"
labelled 11 12 13
has_record 11 13
run
assert_status "$STATUS" 1            "exits non-zero so a gate can branch on it"
assert_has "$OUT" "#12"              "names the PR missing its record"
assert_lacks "$OUT" "#11"            "leaves the intact PRs alone"
assert_lacks "$OUT" "#13"            "leaves the intact PRs alone"
end_sandbox

new_sandbox "the record is looked for on the PR that carries the label"
labelled 42
has_record 7
run
assert_status "$STATUS" 1            "reports the orphan"
assert_has "$(cat "$GH_FIXTURES/fetched")" "42" "fetched comments for the labelled PR"
assert_lacks "$(cat "$GH_FIXTURES/fetched")" "7" "fetched nothing for any other PR"
end_sandbox

new_sandbox "no labelled PRs at all"
labelled
run
assert_status "$STATUS" 0            "exits clean"
assert_has "$OUT" "no"               "says there was nothing to check"
assert_lacks "$(cat "$GH_FIXTURES/fetched" 2>/dev/null || echo)" "#" "fetches no comments"
end_sandbox

new_sandbox "the state defaults to open and is widened by flag"
labelled 11
has_record 11
run
assert_has "$(cat "$GH_FIXTURES/listed")" "--state open" "defaults to open PRs"
end_sandbox

new_sandbox "--state all reaches the PRs already merged in this state"
labelled 11
has_record 11
run --state all
assert_has "$(cat "$GH_FIXTURES/listed")" "--state all" "passes the state through"
end_sandbox

new_sandbox "a listing that fails is an error, not a clean audit"
labelled 11
touch "$GH_FIXTURES/list_fails"
run
assert_status "$STATUS" 2            "distinct from both a clean and a dirty audit"
assert_lacks "$OUT" "no PRs"         "does not report an empty repo it never read"
end_sandbox

# --- summary ------------------------------------------------------------

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
