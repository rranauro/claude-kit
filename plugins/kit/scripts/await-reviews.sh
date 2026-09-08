#!/usr/bin/env bash
# Drive a PR's automated review round to completion, or until a ceiling expires.
#
#   await-reviews.sh <pr> [--repo owner/name] [--ceiling-seconds N]
#                         [--poll-seconds N] [--no-request]
#
# Called once from kit:ticket-loop Phase 5, which opens the PR as a draft and
# closes the review round locally before marking it ready. The alternative it
# replaces was collating on a runner after a second CI round — a round spent
# re-verifying fixes a machine with the implementing context could have made
# and verified before the PR was ever ready to merge.
#
# Three things happen here, in an order the platform dictates rather than one
# chosen for convenience:
#
#   1. Wait for CI to complete. Copilot's review is gated behind completion
#      (not success — a red PR still gets reviewed), and a reviewer requested
#      while CI is running is silently discarded: the API returns 200 with a
#      normal PR object, `requested_reviewers` reads empty either way, and no
#      run ever starts. There is no signal distinguishing that from success, so
#      the only safe move is to not ask until CI is done.
#   2. Request the review. Nothing else produces one where automatic review is
#      off, which is the configuration this exists for — leaving it on as well
#      yields two reviews per PR, the second landing after the round has closed.
#   3. Wait for both reviews, and name on stdout any that did not arrive.
#
# A prose poll loop would cost one Bash round-trip per poll, and every
# round-trip re-sends the caller's whole conversation. Blocking here is one
# call, and it makes the ceiling a literal rather than something a model under
# load re-derives.
#
# Presence only. /kit:review-copilot Step 2 still fetches the review *content*,
# because it also runs standalone against any PR. Splitting the jobs that way
# means drift in this file degrades to a timeout, never to a missed finding.
set -uo pipefail

# One ceiling covers all three stages, because they are one wait from the
# caller's side and splitting it would ask the caller to reason about a budget
# it cannot influence. Fifteen minutes covers a CI cycle of several minutes
# plus the two-and-a-half a review takes after it, with margin. The flags exist
# so tests/ can drive the timeout path without sleeping that long — not for
# tuning.
CEILING=900
POLL=15
REQUEST=1
REPO=""
PR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)             REPO="$2"; shift 2 ;;
    --ceiling-seconds)  CEILING="$2"; shift 2 ;;
    --poll-seconds)     POLL="$2"; shift 2 ;;
    --no-request)       REQUEST=0; shift ;;
    -h|--help)          sed -n '2,5p' "$0"; exit 0 ;;
    *)                  PR="$1"; shift ;;
  esac
done

[ -n "$PR" ] || { echo "error: no PR number given" >&2; exit 1; }

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
fi
[ -n "$REPO" ] || { echo "error: could not resolve repo" >&2; exit 1; }

# The slug GitHub accepts as a reviewer and the login the resulting review is
# authored under. Both spellings appear below; neither is interchangeable with
# the other.
COPILOT_SLUG='copilot-pull-request-reviewer[bot]'
COPILOT_CHECK='copilot-pull-request-reviewer'

# Keyed on the review record, not on inline comments. A review that found
# nothing still posts a top-level record but leaves no inline comments, so a
# check keyed on comments would wait out the whole ceiling on every clean PR —
# the defect this script exists to remove, relocated.
#
# Matched case-insensitively: Copilot's inline comments are authored by login
# `Copilot`, its top-level review by `copilot-pull-request-reviewer[bot]`, and a
# case-sensitive match sees neither.
#
# `github-actions` is deliberately not matched here, though review-copilot.md
# accepts it when collecting content. There it is a catch-all that costs
# nothing; here it would end the wait on any unrelated bot review and collate a
# Copilot review that had not been written yet.
copilot_arrived() {
  gh api "repos/$REPO/pulls/$PR/reviews" --jq '.[].user.login' 2>/dev/null \
    | grep -qiE 'copilot'
}

# The reviewer posts under a human account, so the marker is the only
# authoritative way to find it. Note the issues endpoint — PR-level comments
# do not appear on pulls/comments.
claude_arrived() {
  [ -n "$(gh api "repos/$REPO/issues/$PR/comments" \
            --jq '.[] | select(.body | startswith("<!-- claude-pr-review -->")) | .id' \
            2>/dev/null)" ]
}

# Complete when every check run on the head commit has reported completion, and
# at least one has been created. "At least one" is what stops an empty answer —
# the seconds between opening the PR and CI registering its runs — from reading
# as a finished CI cycle and spending the request on a discard.
#
# Copilot's own review arrives as a check run on the same commit, so counting it
# here would make CI completion depend on the review this waits to request.
ci_complete() {
  local states
  states="$(gh api "repos/$REPO/commits/$(head_sha)/check-runs" \
              --jq ".check_runs[] | select(.name != \"$COPILOT_CHECK\") | .status" \
              2>/dev/null)"
  [ -n "$states" ] || return 1
  ! printf '%s\n' "$states" | grep -qv '^completed$'
}

head_sha() {
  gh api "repos/$REPO/pulls/$PR" --jq '.head.sha' 2>/dev/null
}

SECONDS=0

# Stage 1 — CI. Skipped entirely where the review is already in, which is the
# case on a re-run against a PR whose round has already closed.
ci_at=""
if [ "$REQUEST" -eq 1 ] && ! copilot_arrived; then
  while :; do
    ci_complete && { ci_at=$SECONDS; break; }
    [ "$SECONDS" -ge "$CEILING" ] && break
    sleep "$POLL"
  done
fi

# Stage 2 — the request. Only once CI has completed: firing it earlier is the
# silent discard described at the top, and reporting the review as missing after
# a full ceiling is a better failure than a request nobody can tell was lost.
if [ "$REQUEST" -eq 1 ] && [ -n "$ci_at" ]; then
  if gh api --method POST "repos/$REPO/pulls/$PR/requested_reviewers" \
       -f "reviewers[]=$COPILOT_SLUG" >/dev/null 2>&1; then
    echo "copilot: review requested after CI completed at ${ci_at}s"
  else
    echo "copilot: review request failed — carrying on with what lands"
  fi
elif [ "$REQUEST" -eq 1 ]; then
  echo "copilot: CI did not complete within ${CEILING}s, so no review was requested"
fi

# Stage 3 — the reviews themselves.
copilot_at=""
claude_at=""

while :; do
  [ -n "$copilot_at" ] || { copilot_arrived && copilot_at=$SECONDS; }
  [ -n "$claude_at" ]  || { claude_arrived  && claude_at=$SECONDS; }

  [ -n "$copilot_at" ] && [ -n "$claude_at" ] && break
  [ "$SECONDS" -ge "$CEILING" ] && break
  sleep "$POLL"
done

missing=""
report() { # label arrival-time
  if [ -n "$2" ]; then
    printf '%s: arrived after %ss\n' "$1" "$2"
  else
    printf '%s: did not arrive within %ss\n' "$1" "$CEILING"
    missing="${missing:+$missing }$1"
  fi
}

report copilot       "$copilot_at"
report claude-review "$claude_at"

# The caller reads this line to decide what it is collating. Naming the absent
# source is the whole contract: a silent partial collation is worse than a slow
# one.
printf 'missing: %s\n' "${missing:-none}"

# Always 0, even when a source never arrived or the request was lost. A non-zero
# exit reads as failure to `set -e` and to a model alike, which would turn
# "carry on with what landed" into an escalation. Arrival is reported on stdout,
# never in $?.
exit 0
