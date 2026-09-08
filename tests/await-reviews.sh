#!/usr/bin/env bash
set -uo pipefail

# Every acceptance criterion on #128 that names the wait is asserted here, with
# `gh` stubbed on PATH so GitHub's answers are fixtures rather than network
# calls.
#
# Two properties need a fixture to be testable at all. A review that found
# nothing still has to end the wait — poll a source that only reports inline
# comments and every clean PR burns the whole ceiling, which is the defect this
# ticket removes, relocated. And a source that never arrives has to leave the
# exit status at 0, because a non-zero exit reads as failure to `set -e` and to
# a model alike, turning "carry on with what landed" into an escalation.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/plugins/kit/scripts/await-reviews.sh"
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

assert_at_most() { # actual ceiling label
  if [ "$1" -le "$2" ]; then ok "$3"
  else bad "$3"; printf '       was %s, expected at most %s\n' "$1" "$2" >&2; fi
}

# --- sandbox ------------------------------------------------------------

new_sandbox() {
  current="$1"
  echo "==> $current"
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  GH_FIXTURES="$SANDBOX/fixtures"
  mkdir -p "$GH_FIXTURES" "$SANDBOX/bin"

  # The stub answers the two presence endpoints from fixture files holding
  # exactly what `--jq` would have left on stdout: logins for the reviews
  # endpoint, comment ids for the marker. It ignores the expression itself —
  # gh's embedded jq is not reimplementable here — so the login match under
  # test is the script's own, which is the half that has a documented trap.
  #
  # A `<key>.at` fixture replaces `<key>` once that endpoint has been polled
  # the number of times in `<key>.atN`. That is the only way to hold "arrives
  # on a later poll" still without letting the test depend on wall-clock luck.
  cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
if [ "$1" = "repo" ]; then echo "owner/repo"; exit 0; fi
if [ "$1" = "api" ]; then
  case "$2" in
    */pulls/*/reviews)   key=reviews ;;
    */issues/*/comments) key=comments ;;
    *) exit 0 ;;
  esac
  n=$(( $(cat "$GH_FIXTURES/$key.count" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$GH_FIXTURES/$key.count"
  if [ -f "$GH_FIXTURES/$key.at" ] && [ "$n" -ge "$(cat "$GH_FIXTURES/$key.atN")" ]; then
    cat "$GH_FIXTURES/$key.at"; exit 0
  fi
  cat "$GH_FIXTURES/$key" 2>/dev/null
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

# What `--jq '.[].user.login'` leaves on stdout for the reviews endpoint.
reviews()      { printf '%s\n' "$@" > "$GH_FIXTURES/reviews"; }
# What the same call leaves once the endpoint has been polled $1 times.
reviews_at()   { local n="$1"; shift; echo "$n" > "$GH_FIXTURES/reviews.atN"
                 printf '%s\n' "$@" > "$GH_FIXTURES/reviews.at"; }
# What `--jq '… select(startswith(marker)) … .id'` leaves for the comments endpoint.
marker()       { printf '%s\n' "$@" > "$GH_FIXTURES/comments"; }
marker_at()    { local n="$1"; shift; echo "$n" > "$GH_FIXTURES/comments.atN"
                 printf '%s\n' "$@" > "$GH_FIXTURES/comments.at"; }

run() { # extra args -> sets OUT and STATUS
  OUT="$("$SCRIPT" 128 --repo owner/repo --poll-seconds 1 "$@" 2>&1)"
  STATUS=$?
}

# --- cases --------------------------------------------------------------

new_sandbox "both reviews already present"
reviews "copilot-pull-request-reviewer[bot]"
marker "9001"
SECONDS=0
run --ceiling-seconds 20
elapsed=$SECONDS
assert_status "$STATUS" 0        "exits 0"
assert_has "$OUT" "copilot: arrived"       "reports copilot arrived"
assert_has "$OUT" "claude-review: arrived" "reports the claude review arrived"
assert_has "$OUT" "missing: none"          "names nothing missing"
assert_at_most "$elapsed" 5      "returns immediately rather than polling to the ceiling"
end_sandbox

new_sandbox "a review that found nothing still ends the wait"
# The clean-review case: a top-level record exists, no inline comments anywhere.
# Keyed on the review record precisely so this does not run to the ceiling.
reviews "copilot-pull-request-reviewer[bot]"
marker "9001"
SECONDS=0
run --ceiling-seconds 20
assert_at_most "$SECONDS" 5      "does not wait out the ceiling for inline comments"
assert_has "$OUT" "missing: none" "counts the empty review as arrived"
end_sandbox

new_sandbox "copilot's inline login is matched case-insensitively"
# Copilot's inline comments are authored by login `Copilot`, its top-level
# review by `copilot-pull-request-reviewer[bot]`. A case-sensitive match sees
# neither and waits out the ceiling on a review that is already there.
reviews "Copilot"
marker "9001"
run --ceiling-seconds 20
assert_has "$OUT" "copilot: arrived" "matches a capital-C login"
end_sandbox

new_sandbox "an unrelated reviewer is not mistaken for copilot"
reviews "octocat" "dependabot[bot]"
marker "9001"
run --ceiling-seconds 2
assert_has "$OUT" "copilot: did not arrive" "does not count a human review as copilot's"
assert_has "$OUT" "missing: copilot"        "names copilot as missing"
end_sandbox

new_sandbox "a source arriving on a later poll is detected"
reviews ""
reviews_at 3 "copilot-pull-request-reviewer[bot]"
marker "9001"
run --ceiling-seconds 20
assert_status "$STATUS" 0            "exits 0"
assert_has "$OUT" "copilot: arrived"  "picks up the review once it lands"
assert_has "$OUT" "missing: none"     "names nothing missing"
end_sandbox

new_sandbox "copilot times out, the claude review landed"
reviews ""
marker "9001"
run --ceiling-seconds 2
assert_status "$STATUS" 0                       "exits 0 on a timeout"
assert_has "$OUT" "copilot: did not arrive"      "names the source that did not arrive"
assert_has "$OUT" "claude-review: arrived"       "reports the one that did"
assert_has "$OUT" "missing: copilot"             "summary names copilot"
assert_lacks "$OUT" "missing: copilot claude-review" "does not name the source that landed"
end_sandbox

new_sandbox "the claude review times out, copilot landed"
reviews "copilot-pull-request-reviewer[bot]"
marker ""
run --ceiling-seconds 2
assert_status "$STATUS" 0                          "exits 0 on a timeout"
assert_has "$OUT" "claude-review: did not arrive"   "names the marker as missing"
assert_has "$OUT" "missing: claude-review"          "summary names the claude review"
end_sandbox

new_sandbox "neither review arrives"
reviews ""
marker ""
run --ceiling-seconds 2
assert_status "$STATUS" 0                     "still exits 0 — a timeout is not a failure"
assert_has "$OUT" "missing: copilot"           "names copilot"
assert_has "$OUT" "missing: copilot claude-review" "names both on one line"
end_sandbox

new_sandbox "an unmarked comment is not the claude review"
reviews "copilot-pull-request-reviewer[bot]"
marker ""
run --ceiling-seconds 2
assert_has "$OUT" "claude-review: did not arrive" "an issue comment without the marker does not count"
end_sandbox

new_sandbox "no PR argument"
OUT="$("$SCRIPT" 2>&1)"; STATUS=$?
assert_status "$STATUS" 1        "usage error exits non-zero"
assert_has "$OUT" "error"        "says what was wrong"
end_sandbox

# --- summary ------------------------------------------------------------

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
