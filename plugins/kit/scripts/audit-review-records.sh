#!/usr/bin/env bash
set -uo pipefail

# Which PRs claim a closed review round without carrying the round's record.
#
# `kit-review-closed` is a claim about a `<!-- kit-review-closed -->` comment,
# and the label is what every gate reads — so a PR carrying the label without
# the comment is skipped by everything downstream and never surfaces on its
# own. `/kit:review-copilot` will not create that state any more, but a repo
# that ran the earlier version is already in it, and nothing reports it.
#
# This is a loop rather than a one-liner because the comment cannot be seen
# from the PR list: one fetch per labelled PR is the cost of the answer, which
# is also why no gate pays it on every firing.

usage() {
  cat <<'USAGE'
usage: audit-review-records.sh [--state open|closed|merged|all] [--limit N]

  --state   which PRs to audit (default: open — the ones a gate still skips)
  --limit   how many to take from the listing (default: 200)

exit 0  every labelled PR carries its record
exit 1  at least one does not; each is named on stdout
exit 2  the audit could not run
USAGE
}

LABEL="kit-review-closed"
MARKER="<!-- kit-review-closed -->"
state="open"
limit="200"

while [ $# -gt 0 ]; do
  case "$1" in
    --state) state="${2:-}"; shift 2 ;;
    --limit) limit="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "audit-review-records.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# A failed listing must not read as an empty one. Capturing separately from the
# assignment is what preserves gh's status — `local`/`x=$(…)` would swallow it.
prs="$(gh pr list --label "$LABEL" --state "$state" --limit "$limit" \
         --json number --jq '.[].number' 2>&1)"
if [ $? -ne 0 ]; then
  echo "audit-review-records.sh: could not list PRs labelled $LABEL" >&2
  printf '%s\n' "$prs" >&2
  exit 2
fi

prs="$(printf '%s\n' "$prs" | grep -E '^[0-9]+$' || true)"

if [ -z "$prs" ]; then
  echo "no $state PRs carry $LABEL — nothing to audit"
  exit 0
fi

checked=0
orphans=()

while IFS= read -r n; do
  [ -n "$n" ] || continue
  checked=$((checked + 1))
  # startswith rather than contains: the marker opens the comment's first line,
  # and a summary quoting the marker in its body is not the record.
  count="$(gh api "repos/{owner}/{repo}/issues/$n/comments" \
             --jq "[.[] | select(.body | startswith(\"$MARKER\"))] | length" 2>/dev/null)"
  # An unreadable PR is reported as an orphan rather than skipped. The whole
  # point is to over-report: a false name costs one look, a missed one costs
  # the decision.
  case "$count" in
    ''|*[!0-9]*) orphans+=("$n") ;;
    0)           orphans+=("$n") ;;
  esac
done <<< "$prs"

if [ "${#orphans[@]}" -eq 0 ]; then
  echo "all $checked $state PRs labelled $LABEL carry their record"
  exit 0
fi

for n in "${orphans[@]}"; do
  echo "#$n — labelled $LABEL with no record comment"
done
echo
echo "${#orphans[@]} of $checked $state PRs labelled $LABEL carry no record"
echo "Each one reads as triaged to every gate. Re-run the round on it, or"
echo "remove the label so a later pass picks it up:"
echo "  gh pr edit <n> --remove-label $LABEL"
exit 1
