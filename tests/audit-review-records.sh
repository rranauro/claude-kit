#!/usr/bin/env bash
set -uo pipefail

# The audit exists because the state it looks for is invisible by construction:
# the surviving mark is the one that tells every reader to look no further. So
# the cases below are mostly about the two answers not being confusable — a PR
# whose record is present must never be named, and one whose record is absent
# must be, with an exit status a gate can branch on.
#
# `gh` is stubbed on PATH, because the question is how the script bins the
# answer, not what GitHub returns. One call carries both halves — the PR number
# and how many of its comments opened with the marker — so the fixture is one
# line per labelled PR and the stub does no matching of its own.

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

  # The stub records the arguments and replays a fixture. It does not run the
  # `--jq` expression — gh's embedded jq is not reimplementable here — so the
  # marker match itself is pinned by asserting on the recorded arguments, and
  # the binning is pinned by the fixture's counts.
  cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
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
        printf '%s\n' "$n" >> "$GH_FIXTURES/confirmed"
        cat "$GH_FIXTURES/confirm.$n" 2>/dev/null || echo 0
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

# What the one `gh pr list --json number,comments --jq` call leaves on stdout:
# "<pr-number> <how many of its comments opened with the marker>".
rows() { printf '%s\n' "$@" > "$GH_FIXTURES/prs"; }
# How many marker comments the paginated confirming fetch finds on PR $1. The
# listing's comment page is bounded, so a PR reporting none is asked again.
confirm() { echo "$2" > "$GH_FIXTURES/confirm.$1"; }

run() {
  OUT="$("$SCRIPT" "$@" 2>&1)"
  STATUS=$?
}

# --- cases --------------------------------------------------------------

new_sandbox "every labelled PR carries its record"
rows "11 1" "12 1"
run
assert_status "$STATUS" 0            "exits clean"
assert_lacks "$OUT" "#11"            "names no PR"
assert_lacks "$OUT" "#12"            "names no PR"
assert_has "$OUT" "2"                "reports how many it checked"
end_sandbox

new_sandbox "a labelled PR with no record is named"
rows "11 1" "12 0" "13 1"
run
assert_status "$STATUS" 1            "exits non-zero so a gate can branch on it"
assert_has "$OUT" "#12"              "names the PR missing its record"
assert_lacks "$OUT" "#11"            "leaves the intact PRs alone"
assert_lacks "$OUT" "#13"            "leaves the intact PRs alone"
end_sandbox

new_sandbox "the record is the marker opening a comment, not appearing in one"
rows "11 1"
run
# A summary that quotes the marker mid-body is not the record, so the match has
# to anchor. The expression is gh's to run; what this pins is that the script
# asked for the anchored form against the marker it documents.
assert_has "$(cat "$GH_FIXTURES/listed")" "startswith" "anchors the match"
assert_has "$(cat "$GH_FIXTURES/listed")" "<!-- kit-review-closed -->" "matches the marker it documents"
end_sandbox

new_sandbox "the record is read in the call that finds the labelled PRs"
rows "11 1"
run
# The per-PR fetch this replaced read only the first page of a PR's comments,
# so a busy PR was reported as an orphan on every run and never self-cleared.
assert_has "$(cat "$GH_FIXTURES/listed")" "--json number,comments" "asks for the comments up front"
assert_status "$(grep -c . "$GH_FIXTURES/listed")" 1 "spends one call, whatever the PR count"
end_sandbox

new_sandbox "no labelled PRs at all"
rows
run
assert_status "$STATUS" 0            "exits clean"
assert_has "$OUT" "no"               "says there was nothing to check"
end_sandbox

new_sandbox "the state defaults to open"
rows "11 1"
run
assert_has "$(cat "$GH_FIXTURES/listed")" "--state open" "audits the PRs a gate still skips"
end_sandbox

new_sandbox "--state all reaches the PRs already merged in this state"
rows "11 1"
run --state all
assert_has "$(cat "$GH_FIXTURES/listed")" "--state all" "passes the state through"
end_sandbox

new_sandbox "a flag given no value is a usage error, not a spin"
rows "11 1"
# `shift 2` with one argument left shifts nothing, so the argument loop never
# drains and the script never reaches the work. It reads as a hang rather than
# a mistyped flag, which is the one failure an audit tool cannot afford.
OUT="$(perl -e 'alarm 5; exec @ARGV' "$SCRIPT" --state 2>&1)"
STATUS=$?
assert_status "$STATUS" 2            "exits on the bad argument"
assert_has "$OUT" "usage"            "says what the arguments are"
end_sandbox

new_sandbox "an unknown argument is refused rather than ignored"
rows "11 1"
run --wat
assert_status "$STATUS" 2            "does not audit under arguments it did not understand"
assert_has "$OUT" "--wat"            "names the argument it refused"
end_sandbox

new_sandbox "a listing that fails is an error, not a clean audit"
rows "11 1"
touch "$GH_FIXTURES/list_fails"
run
assert_status "$STATUS" 2            "distinct from both a clean and a dirty audit"
assert_lacks "$OUT" "no PRs"         "does not report an empty repo it never read"
end_sandbox

new_sandbox "a PR reporting no record is confirmed before it is named"
rows "11 1" "12 0"
confirm 12 1
run
# `--json comments` returns a bounded page, so a busy PR can report zero while
# carrying its marker past the cutoff. Naming it would be a false positive that
# recurs every run and never self-clears.
assert_status "$STATUS" 0            "the confirmed record clears it"
assert_lacks "$OUT" "#12"            "does not name a PR whose marker was past the page"
assert_has "$(cat "$GH_FIXTURES/confirmed")" "12" "asked again about the PR reporting none"
assert_lacks "$(cat "$GH_FIXTURES/confirmed")" "11" "spends nothing on the PRs already answered"
end_sandbox

new_sandbox "a PR with no record anywhere is still named"
rows "11 0"
confirm 11 0
run
assert_status "$STATUS" 1            "reports the orphan"
assert_has "$OUT" "#11"              "names it"
end_sandbox

new_sandbox "a listing filled to the limit is not a clean audit"
rows "11 1" "12 1"
run --limit 2
# Every row the listing could hold came back, so there may be labelled PRs it
# never saw. Reporting clean here claims an exhaustiveness the call cannot give.
assert_status "$STATUS" 2            "does not claim an audit it could not finish"
assert_has "$OUT" "--limit"          "says how to widen it"
end_sandbox

# --- summary ------------------------------------------------------------

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
