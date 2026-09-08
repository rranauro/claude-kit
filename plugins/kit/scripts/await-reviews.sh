#!/usr/bin/env bash
# Block until both automated reviews have landed on a PR, or a ceiling expires.
#
#   await-reviews.sh <pr> [--repo owner/name] [--ceiling-seconds N]
#                         [--poll-seconds N]
#
# Called once from kit:ticket-loop Phase 5, which opens the PR as a draft and
# closes the review round locally before marking it ready. The alternative it
# replaces was letting a CI run stand in as the timer: CI takes several minutes
# and Copilot answers in about one, so waiting for the runner was a convenient
# way to be sure Copilot had spoken — at the cost of a whole CI round spent
# verifying nothing.
#
# A prose poll loop would cost one Bash round-trip per poll, and every
# round-trip re-sends the caller's whole conversation. Blocking here is one
# call, and it makes the ceiling a literal rather than something a model under
# load re-derives.
#
# Presence only. /kit:review-copilot Step 2 still fetches the review *content*,
# because it also runs standalone against any PR. Splitting the jobs that way
# means drift in this file degrades to a timeout, never to a missed finding.
#
# Nothing here requests a review or configures who performs one. Whether
# Copilot reviews a draft at all is the consuming project's question; this
# script is correct either way, because a review that never comes is reported
# by name and the pass carries on with what landed.
set -uo pipefail

# Copilot answers in about a minute; the Claude review is a headless `claude -p`
# run and is the slower of the two. Five minutes covers it with margin and still
# costs less than the CI round this replaces. The flags exist so tests/ can
# drive the timeout path without sleeping for five minutes — not for tuning.
CEILING=300
POLL=15
REPO=""
PR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)             REPO="$2"; shift 2 ;;
    --ceiling-seconds)  CEILING="$2"; shift 2 ;;
    --poll-seconds)     POLL="$2"; shift 2 ;;
    -h|--help)          sed -n '2,7p' "$0"; exit 0 ;;
    *)                  PR="$1"; shift ;;
  esac
done

[ -n "$PR" ] || { echo "error: no PR number given" >&2; exit 1; }

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
fi
[ -n "$REPO" ] || { echo "error: could not resolve repo" >&2; exit 1; }

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

copilot_at=""
claude_at=""
SECONDS=0

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

# Always 0, even when a source never arrived. A non-zero exit reads as failure
# to `set -e` and to a model alike, which would turn "carry on with what
# landed" into an escalation. Arrival is reported on stdout, never in $?.
exit 0
