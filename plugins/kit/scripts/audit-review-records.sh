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
# One call answers it: `gh pr list --json` returns each PR's comments, so the
# marker is matched inside the same request that finds the labelled PRs. The
# per-PR fetch this replaced also read only the first page of comments, which
# reported any busy PR as an orphan on every run.

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

die() { echo "audit-review-records.sh: $*" >&2; usage >&2; exit 2; }

while [ $# -gt 0 ]; do
  # A flag whose value is missing must not reach `shift 2` — with one argument
  # left it shifts nothing, the loop never drains, and a typo reads as a hang.
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state="$2"; shift 2 ;;
    --limit) [ $# -ge 2 ] || die "--limit needs a value"; limit="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# startswith rather than contains: the marker opens the comment's first line,
# and a summary quoting the marker in its body is not the record.
rows="$(gh pr list --label "$LABEL" --state "$state" --limit "$limit" \
          --json number,comments \
          --jq ".[] | \"\(.number) \([.comments[].body | select(startswith(\"$MARKER\"))] | length)\"" 2>&1)"
if [ $? -ne 0 ]; then
  echo "audit-review-records.sh: could not list PRs labelled $LABEL" >&2
  printf '%s\n' "$rows" >&2
  exit 2
fi

rows="$(printf '%s\n' "$rows" | grep -E '^[0-9]+ [0-9]+$' || true)"

if [ -z "$rows" ]; then
  echo "no $state PRs carry $LABEL — nothing to audit"
  exit 0
fi

checked=0
orphans=()

while read -r n records; do
  [ -n "$n" ] || continue
  checked=$((checked + 1))
  [ "$records" -eq 0 ] && orphans+=("$n")
done <<< "$rows"

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
