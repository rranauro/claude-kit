#!/usr/bin/env bash
set -uo pipefail

# What the append script owns, asserted against a throwaway repository with a
# linked worktree.
#
# The store is gitignored and lives outside the repo, so `scripts/lint.sh`
# cannot reach a single record. A malformed line is therefore unrecoverable and
# invisible — which is why the script builds the JSON rather than a model, and
# why the assertions below are mostly about one record staying on one line.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/plugins/kit/scripts/observe.sh"

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

assert_eq() { # actual expected label
  if [ "$1" = "$2" ]; then ok "$3"
  else bad "$3"; printf '       expected: %s\n       actual:   %s\n' "$2" "$1" >&2; fi
}

# --- reading the store --------------------------------------------------

lines() { grep -c . "$STORE" 2>/dev/null || echo 0; }

# Every line parses as JSON on its own — the one property JSONL has to hold and
# the one nothing else in this repo can check.
assert_jsonl_valid() { # label
  local out
  out="$(python3 - "$STORE" <<'PY' 2>&1
import json, sys
for n, line in enumerate(open(sys.argv[1]), 1):
    if not line.strip():
        continue
    try:
        json.loads(line)
    except Exception as e:
        print(f"line {n}: {e}")
        sys.exit(1)
PY
)"
  if [ -z "$out" ]; then ok "$1"
  else bad "$1"; printf '       %s\n' "$out" >&2; fi
}

field() { # record-index(1-based) dotted-path
  python3 - "$STORE" "$1" "$2" <<'PY'
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
v = recs[int(sys.argv[2]) - 1]
for k in sys.argv[3].split("."):
    v = v[k]
print(v if isinstance(v, str) else json.dumps(v))
PY
}

set_fields() { # record-index(1-based) key value [key value ...]
  python3 - "$STORE" "$@" <<'PY'
import json, sys
path, idx, kv = sys.argv[1], int(sys.argv[2]) - 1, sys.argv[3:]
recs = [json.loads(l) for l in open(path) if l.strip()]
for k, v in zip(kv[::2], kv[1::2]):
    recs[idx][k] = v
open(path, "w").write("".join(json.dumps(r) + "\n" for r in recs))
PY
}

# --- sandbox ------------------------------------------------------------

new_sandbox() {
  current="$1"
  echo "==> $current"
  # -P: mktemp hands back /var/... on macOS while git reports /private/var/...,
  # and the store's path is compared against both below.
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  MAIN="$SANDBOX/main"
  STORE="$MAIN/.claude/observations.jsonl"

  # `git init -b` is 2.28+; this suite builds its sandbox on whatever git the
  # runner ships, so the default branch is named the long way round. Nothing
  # here fetches or pushes, so the remote is a URL rather than a repository —
  # `ctx.repo` is the only thing any test reads off it.
  git init -q "$MAIN"
  git -C "$MAIN" symbolic-ref HEAD refs/heads/main
  git -C "$MAIN" config user.email test@example.com
  git -C "$MAIN" config user.name "Test"
  git -C "$MAIN" remote add origin git@github.com:acme/widgets.git
  echo hello > "$MAIN/README.md"
  git -C "$MAIN" add -A
  git -C "$MAIN" commit -qm initial
}

end_sandbox() {
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
}

add_worktree() { # branch
  git -C "$MAIN" worktree add -q "$MAIN/.claude/worktrees/$1" -b "$1" main
}

# A complete, valid append from the main checkout. Callers override with "$@".
record() { # cwd extra-args...
  local cwd="$1"; shift
  (cd "$cwd" && "$SCRIPT" \
    --by "kit:grilling" \
    --claim "plugins/kit/skills/grilling/SKILL.md names no destination for the Parked list" \
    --check "grep -c hello README.md" \
    --surfaced "Grilling #150 ended with three parked items and nowhere to put them." \
    --action "this backlog" \
    --who "agent" \
    --affected "a pass that ends a grilling reads the skill for where Parked items go, and finds nothing, so it drops them" \
    "$@" 2>&1)
}

# ========================================================================
# AC · A record is a claim, the command that tests it, and that command's
#      answer at the time.
# ========================================================================

new_sandbox "a record carries the claim, its check, and the check's own answer"
out="$(record "$MAIN" --check "printf 'seven\n'")"
assert_eq "$?" 0 "the append succeeds"
assert_eq "$(lines)" "1" "one record is appended"
assert_jsonl_valid "the record is valid JSON on one line"
assert_eq "$(field 1 claim)" \
  "plugins/kit/skills/grilling/SKILL.md names no destination for the Parked list" \
  "the claim is stored verbatim"
assert_eq "$(field 1 check)" "printf 'seven\n'" "the check is stored verbatim"
assert_eq "$(field 1 witness)" "seven" \
  "the witness is the check's own output, not a value the caller supplied"
assert_eq "$(field 1 by)" "kit:grilling" "the producing pass is named"
assert_has "$(field 1 surfaced)" "three parked items" "the thread that exposed it survives"
assert_eq "$(field 1 action)" "this backlog" "the destination is recorded"
assert_eq "$(field 1 v)" "2" "the record carries the schema version that has who and affected"
assert_eq "$(field 1 who)" "agent" "who is affected is recorded"
assert_has "$(field 1 affected)" "finds nothing, so it drops them" \
  "and what they get instead of what they expect"
end_sandbox

new_sandbox "the witness is captured even when the check fails"
out="$(record "$MAIN" --check "grep -c nothing-matches-this README.md")"
assert_eq "$?" 0 "a check that exits non-zero is still a usable check"
assert_eq "$(field 1 witness)" "0" "its output is the witness"
end_sandbox

# ========================================================================
# AC · An observation is recoverable by someone who was not in the session,
#      and carries what the pass was processing.
# ========================================================================

new_sandbox "the record names what the pass was working on"
add_worktree 150-closing-observation
out="$(record "$MAIN/.claude/worktrees/150-closing-observation")"
assert_eq "$(field 1 ctx.repo)" "acme/widgets" "the repository is recorded"
assert_eq "$(field 1 ctx.branch)" "150-closing-observation" "the branch is recorded"
assert_eq "$(field 1 ctx.issue)" "150" \
  "the issue is read off the branch when the caller does not name one"
end_sandbox

new_sandbox "an explicitly named issue and PR win over the branch"
add_worktree 150-closing-observation
out="$(record "$MAIN/.claude/worktrees/150-closing-observation" --issue 42 --pr 77)"
assert_eq "$(field 1 ctx.issue)" "42" "the named issue is recorded"
assert_eq "$(field 1 ctx.pr)" "77" "the named PR is recorded"
end_sandbox

# ========================================================================
# AC · A record written mid-ticket survives the worktree it was written in.
# ========================================================================

new_sandbox "the store is at the main checkout, not the worktree"
add_worktree 150-closing-observation
out="$(record "$MAIN/.claude/worktrees/150-closing-observation")"
assert_eq "$(lines)" "1" "the record lands in the main checkout's store"
if [ -e "$MAIN/.claude/worktrees/150-closing-observation/.claude/observations.jsonl" ]
then bad "nothing is written inside the worktree"
else ok "nothing is written inside the worktree"; fi
assert_has "$out" "$MAIN/.claude/observations.jsonl" "the reported path is the main one"
end_sandbox

# ========================================================================
# AC · The store stays out of version control without a tracked ignore rule.
# ========================================================================

new_sandbox "the store is excluded per-clone, once"
record "$MAIN" >/dev/null
record "$MAIN" >/dev/null
assert_has "$(cat "$MAIN/.git/info/exclude")" ".claude/observations.jsonl" \
  "the exclude rule is written to the per-clone exclude file"
assert_eq "$(grep -c 'observations.jsonl' "$MAIN/.git/info/exclude")" "1" \
  "and only once, however many records are appended"
if [ -f "$MAIN/.gitignore" ]; then
  assert_lacks "$(cat "$MAIN/.gitignore")" "observations" \
    ".gitignore is left alone, so no PR diff carries the rule"
else ok ".gitignore is left alone, so no PR diff carries the rule"; fi
assert_lacks "$(git -C "$MAIN" status --porcelain)" "observations" \
  "so the store never shows up as a change"
end_sandbox

new_sandbox "excluding works from inside a worktree too"
add_worktree 150-closing-observation
record "$MAIN/.claude/worktrees/150-closing-observation" >/dev/null
assert_has "$(cat "$MAIN/.git/info/exclude")" ".claude/observations.jsonl" \
  "the rule lands in the common exclude file, not the worktree's"
assert_lacks "$(git -C "$MAIN" status --porcelain)" "observations" \
  "so the store never shows up as a change in the main checkout either"
end_sandbox

# ========================================================================
# AC · The user can tell an observation was recorded, and how full the
#      drawer is, without going to look.
# ========================================================================

new_sandbox "the append reports the claim, the slug, and the store's size"
out="$(record "$MAIN")"
id="$(field 1 id)"
assert_has "$out" "$id" "the slug is reported so it can be resurfaced"
assert_has "$out" "names no destination for the Parked list" "the claim is reported"
assert_has "$out" "1 observation" "the store's size is reported"
out2="$(record "$MAIN" --claim "docs/commands.md lists no entry for /kit:observe")"
assert_has "$out2" "2 observations" "and it counts up, so a filling drawer says so"
end_sandbox

new_sandbox "two records of the same claim get distinct slugs"
record "$MAIN" >/dev/null
record "$MAIN" >/dev/null
assert_eq "$(lines)" "2" "both records are kept"
if [ "$(field 1 id)" = "$(field 2 id)" ]
then bad "the second record gets its own slug"
else ok "the second record gets its own slug"; fi
end_sandbox

# ========================================================================
# AC · One record is one line, whatever the check printed.
# ========================================================================

new_sandbox "newlines and quotes never break the record onto a second line"
out="$(record "$MAIN" \
  --check "printf 'a \"quoted\" line\nand a second\n\tand a tab\n'" \
  --surfaced "$(printf 'A paragraph.\n\nWith a blank line, a "quote", and a \\backslash.')")"
assert_eq "$(lines)" "1" "the record is still one line"
assert_jsonl_valid "and still parses"
assert_has "$(field 1 witness)" "and a second" "the multi-line witness is intact"
assert_has "$(field 1 surfaced)" "backslash" "and so is the multi-line surfaced text"
end_sandbox

# ========================================================================
# AC · An incomplete record is refused rather than written half-formed.
# ========================================================================

new_sandbox "a record missing a required part is refused"
for missing in claim check surfaced action by who affected; do
  args=()
  for opt in by claim check surfaced action who affected; do
    [ "$opt" = "$missing" ] || args+=("--$opt" "x")
  done
  out="$( (cd "$MAIN" && "$SCRIPT" "${args[@]}") 2>&1 )"
  st=$?
  assert_eq "$st" 2 "--$missing omitted is a usage error"
  assert_has "$out" "$missing" "and the message names what was missing"
done
assert_eq "$(lines)" "0" "nothing half-formed is written"
end_sandbox

# `timeout` is coreutils and macOS lacks it, so a hang is bounded by hand: a
# looping parser is killed after five seconds and reads as exit 143, not 2.
bounded() {
  "$@" & local pid=$!
  ( sleep 5; kill "$pid" 2>/dev/null ) & local dog=$!
  wait "$pid"; local st=$?
  kill "$dog" 2>/dev/null; wait "$dog" 2>/dev/null
  return "$st"
}

new_sandbox "a flag given last with no value is refused, not looped on"
for flag in by who affected issue; do
  out="$( cd "$MAIN" && bounded "$SCRIPT" --claim c --"$flag" 2>&1 )"
  assert_eq "$?" 2 "--$flag with no value is a usage error"
  assert_has "$out" "--$flag" "and the message names the flag"
done
end_sandbox

# ========================================================================
# AC · A finding that affects nobody adds nothing to the store, and the
#      pass's report says it was dropped and why.
# ========================================================================

new_sandbox "a finding that affects nobody is dropped, not recorded"
out="$(record "$MAIN" --who "nobody" \
  --affected "the table has 44 rows, so no query is slow enough for anyone to notice")"
assert_eq "$?" 0 "dropping is not an error, so a producer has nothing to retry"
assert_eq "$(lines)" "0" "nothing is written"
if [ -e "$STORE" ]; then bad "no store is created for it"
else ok "no store is created for it"; fi
assert_has "$out" "dropped" "the printed line says it was dropped"
assert_has "$out" "names no destination for the Parked list" "and names the claim"
assert_has "$out" "affects nobody" "and says why"
assert_has "$out" "44 rows" "in the producer's own words"
end_sandbox

new_sandbox "nobody is matched however it is cased or padded"
out="$(record "$MAIN" --who " Nobody ")"
assert_eq "$(lines)" "0" "nothing is written"
assert_has "$out" "affects nobody" "and it is reported as dropped"
end_sandbox

new_sandbox "a dropped finding leaves the records already in the store alone"
record "$MAIN" >/dev/null
out="$(record "$MAIN" --claim "docs/commands.md lists no entry for /kit:observe" --who nobody)"
assert_eq "$(lines)" "1" "the store keeps exactly what it had"
assert_lacks "$(cat "$STORE")" "/kit:observe" "and the dropped claim is not in it"
end_sandbox

# ========================================================================
# AC · Records already in a store are untouched, and triage still reads them.
# ========================================================================

# A record written before who and affected existed, exactly as that writer
# shaped it.
v1_record() {
  mkdir -p "$(dirname "$STORE")"
  cat >> "$STORE" <<'JSON'
{"v": 1, "id": "an-old-record", "at": "2026-10-01", "by": "kit:grilling", "ctx": {"repo": "acme/widgets", "issue": null, "branch": "main", "pr": null}, "claim": "README.md says hello", "check": "cat README.md", "witness": "hello", "surfaced": "an older pass", "action": "this backlog"}
JSON
}

new_sandbox "a record from before who and affected still lists, rechecks and drops"
v1_record
record "$MAIN" >/dev/null
assert_has "$(sed -n 1p "$STORE")" '"v": 1, "id": "an-old-record"' \
  "appending leaves the old record byte for byte"
out="$( (cd "$MAIN" && "$SCRIPT" list) 2>&1 )"
assert_has "$out" "README.md says hello" "list reads it"
assert_has "$out" "2 observations" "alongside the new one"
out="$( (cd "$MAIN" && "$SCRIPT" recheck an-old-record) 2>&1 )"
assert_has "$out" "holds  an-old-record" "recheck reads it"
echo goodbye > "$MAIN/README.md"
out="$( (cd "$MAIN" && "$SCRIPT" rewitness an-old-record) 2>&1 )"
assert_has "$(field 1 witness)" "goodbye" "rewitness reads it"
assert_lacks "$(sed -n 1p "$STORE")" '"who"' "without inventing who it affects"
out="$( (cd "$MAIN" && "$SCRIPT" drop an-old-record) 2>&1 )"
assert_eq "$?" 0 "drop reads it"
assert_eq "$(lines)" "1" "and removes only it"
end_sandbox

# ========================================================================
# AC · Accumulated observations can be reviewed and cleared down.
# ========================================================================

new_sandbox "list reports every record"
record "$MAIN" >/dev/null
record "$MAIN" --claim "docs/commands.md lists no entry for /kit:observe" >/dev/null
out="$( (cd "$MAIN" && "$SCRIPT" list) 2>&1 )"
assert_has "$out" "Parked list" "the first claim is listed"
assert_has "$out" "lists no entry for /kit:observe" "the second claim is listed"
assert_has "$out" "$(field 1 id)" "with the slug that resurfaces it"
end_sandbox

new_sandbox "list survives a corrupt line and says which"
record "$MAIN" >/dev/null
echo 'this is not json' >> "$STORE"
record "$MAIN" --claim "docs/commands.md lists no entry for /kit:observe" >/dev/null
out="$( (cd "$MAIN" && "$SCRIPT" list) 2>&1 )"
assert_eq "$?" 0 "one corrupt record does not strand the drawer"
assert_has "$out" "Parked list" "the record before it still lists"
assert_has "$out" "lists no entry for /kit:observe" "and so does the one after"
assert_has "$out" "unreadable" "the corrupt line is reported"
end_sandbox

new_sandbox "list says so when the store is empty"
out="$( (cd "$MAIN" && "$SCRIPT" list) 2>&1 )"
assert_eq "$?" 0 "an empty store is not an error"
assert_has "$out" "no observations" "and says so in one line"
end_sandbox

# ========================================================================
# AC · Reviewing the store is re-running the checks, not re-deriving them.
# ========================================================================

new_sandbox "recheck re-runs a record's own check and diffs the witness"
record "$MAIN" --check "cat README.md" >/dev/null
out="$( (cd "$MAIN" && "$SCRIPT" recheck) 2>&1 )"
assert_has "$out" "holds" "an unchanged witness reads as holding"
echo goodbye > "$MAIN/README.md"
out="$( (cd "$MAIN" && "$SCRIPT" recheck) 2>&1 )"
assert_has "$out" "moved" "a witness the repo now contradicts reads as moved"
assert_has "$out" "goodbye" "and the new answer is shown"
end_sandbox

new_sandbox "recheck runs against the main checkout, not the caller's worktree"
add_worktree 150-closing-observation
record "$MAIN" --check "cat README.md" >/dev/null
echo goodbye > "$MAIN/README.md"
out="$( (cd "$MAIN/.claude/worktrees/150-closing-observation" && "$SCRIPT" recheck) 2>&1 )"
assert_has "$out" "moved" "the check sees the main checkout it was written against"
end_sandbox

new_sandbox "recheck ignores a line number that shifted under an unchanged claim"
printf 'a\nneedle here\n' > "$MAIN/README.md"
record "$MAIN" --check "grep -n needle README.md" >/dev/null
printf 'a\nb\nc\nneedle here\n' > "$MAIN/README.md"
out="$( (cd "$MAIN" && "$SCRIPT" recheck) 2>&1 )"
assert_has "$out" "holds" "grep -n output that only moved lines still holds"
printf 'a\nb\nc\nthe needle was reworded\n' > "$MAIN/README.md"
out="$( (cd "$MAIN" && "$SCRIPT" recheck) 2>&1 )"
assert_has "$out" "moved" "but changed text still reads as moved"
end_sandbox

new_sandbox "recheck ignores a shifted line number in the file:line: form"
printf 'needle one\n' > "$MAIN/README.md"
record "$MAIN" --check "grep -Hn needle README.md" >/dev/null
printf 'x\nx\nneedle one\n' > "$MAIN/README.md"
out="$( (cd "$MAIN" && "$SCRIPT" recheck) 2>&1 )"
assert_has "$out" "holds" "README.md:N: prefixes are compared without N"
end_sandbox

new_sandbox "recheck names a check whose path has gone, apart from a moved answer"
printf 'needle\n' > "$MAIN/gone.txt"
(cd "$MAIN" && git add gone.txt && git commit -qm gone)
record "$MAIN" --check "grep -c needle gone.txt" >/dev/null
rm "$MAIN/gone.txt"
out="$( (cd "$MAIN" && "$SCRIPT" recheck) 2>&1 )"
assert_has "$out" "gone " "a check that now fails on a missing path reads as gone"
assert_lacks "$out" "moved" "and not as moved"
end_sandbox

new_sandbox "a check is witnessed against the branch the pass is on, not main"
add_worktree 150-closing-observation
WT="$MAIN/.claude/worktrees/150-closing-observation"
echo 'only on the branch' > "$WT/branch_only.txt"
out="$(record "$WT" --check "cat branch_only.txt")"
assert_has "$out" "observed" "code main lacks can still be recorded against"
assert_has "$(field 1 witness)" "only on the branch" "and the witness is what the branch answered"
end_sandbox

new_sandbox "a check that runs and prints nothing is recorded"
out="$(record "$MAIN" --check "grep nomatch README.md")"
assert_eq "$?" 0 "an absence is a valid witness"
assert_eq "$(lines)" "1" "and the record is written"
assert_eq "$(field 1 witness)" "" "with the empty answer as its witness"
end_sandbox

# ========================================================================
# AC · A check whose shell cannot run one of its commands is refused, and
#      recheck never counts one as holding.
# ========================================================================

new_sandbox "a check that names a command its shell cannot find is refused"
out="$(record "$MAIN" --check "nosuchcmd_318 hello README.md")"
st=$?
assert_eq "$st" 2 "a missing command is a usage error"
assert_has "$out" "nosuchcmd_318" "and the message names the command"
assert_eq "$(lines)" "0" "nothing is written"
end_sandbox

new_sandbox "a missing command inside a pipeline is refused too"
out="$(record "$MAIN" --check "cat README.md | nosuchcmd_318 -c hello")"
assert_eq "$?" 2 "the pipeline's last stage being missing is still caught"
assert_has "$out" "nosuchcmd_318" "and named"
assert_eq "$(lines)" "0" "nothing is written"
end_sandbox

new_sandbox "a missing command inside a nested bash is refused"
out="$(record "$MAIN" --check "bash -c 'nosuchcmd_318 README.md'")"
assert_eq "$?" 2 "the nested shell reports through the same handler"
assert_has "$out" "nosuchcmd_318" "and the command is named"
assert_eq "$(lines)" "0" "nothing is written"
end_sandbox

new_sandbox "a command exec cannot find is refused"
out="$(record "$MAIN" --check "exec nosuchcmd_318 README.md")"
assert_eq "$?" 2 "exit 127 counts as a missing command"
assert_eq "$(lines)" "0" "nothing is written"
end_sandbox

new_sandbox "a check whose answer mentions a missing command is not refused"
echo 'bash: rg: command not found' > "$MAIN/README.md"
out="$(record "$MAIN" --check "grep -c 'command not found' README.md")"
assert_eq "$?" 0 "the phrase in the output is not a missing command"
assert_eq "$(field 1 witness)" "1" "and the witness is the grep's answer"
end_sandbox

new_sandbox "recheck reports a check that cannot run as unrunnable, not holding"
record "$MAIN" >/dev/null
# A record written before the refusal: its witness is already the error, so a
# plain diff would read it as holding forever.
set_fields 1 check "nosuchcmd_318 -c hello README.md" witness "bash: nosuchcmd_318: command not found"
out="$( (cd "$MAIN" && "$SCRIPT" recheck) 2>&1 )"
assert_has "$out" "unrunnable" "a check that cannot run is reported as unrunnable"
assert_lacks "$out" "holds" "and never as holding"
assert_has "$out" "nosuchcmd_318" "naming the command"
end_sandbox

new_sandbox "a bash too old to detect a missing command is refused"
FAKE="$SANDBOX/oldbash"; mkdir -p "$FAKE"
printf '#!/bin/sh\necho 3\n' > "$FAKE/bash"; chmod +x "$FAKE/bash"
REAL_BASH="$(command -v bash)"
out="$( (cd "$MAIN" && PATH="$FAKE:$PATH" "$REAL_BASH" "$SCRIPT" \
  --by x --claim y --check "cat README.md" --surfaced s --action a --who agent --affected z) 2>&1 )"
assert_eq "$?" 1 "append refuses on bash older than 4"
assert_has "$out" "bash 4" "and says what it needs"
assert_eq "$(lines)" "0" "nothing is written"
out="$( (cd "$MAIN" && PATH="$FAKE:$PATH" "$REAL_BASH" "$SCRIPT" recheck) 2>&1 )"
assert_eq "$?" 1 "recheck refuses too"
end_sandbox

new_sandbox "a check whose witness is a missing-path error is refused"
out="$(record "$MAIN" --check "grep -c x no_such_file.txt")"
st=$?
assert_eq "$st" 2 "a missing path is a usage error"
assert_has "$out" "does not exist" "and says why"
assert_eq "$(lines)" "0" "nothing is written"
end_sandbox

new_sandbox "recheck keeps a leading number that grep did not print"
printf '3-column layout\n' > "$MAIN/README.md"
record "$MAIN" --check "cat README.md" >/dev/null
printf '4-column layout\n' > "$MAIN/README.md"
out="$( (cd "$MAIN" && "$SCRIPT" recheck) 2>&1 )"
assert_has "$out" "moved" "a changed leading number is a moved answer without -n"
end_sandbox

new_sandbox "a check that reaches into a worktree is refused"
out="$(record "$MAIN" --check "grep -c x .claude/worktrees/12-foo/app/a.rb")"
st=$?
assert_eq "$st" 2 "a worktree path is a usage error"
assert_has "$out" "worktree" "the message names the worktree"
assert_eq "$(lines)" "0" "nothing is written"
end_sandbox

new_sandbox "rewitness re-captures the named records' witness from the main checkout"
record "$MAIN" --check "cat README.md" >/dev/null
record "$MAIN" --claim "CONTEXT.md has no entry for an observation" --check "cat README.md" >/dev/null
echo goodbye > "$MAIN/README.md"
first="$(field 1 id)"
out="$( (cd "$MAIN" && "$SCRIPT" rewitness "$first") 2>&1 )"
assert_eq "$?" 0 "the rewitness succeeds"
assert_has "$out" "rewitnessed" "and reports what it did"
assert_has "$(field 1 witness)" "goodbye" "the named record carries the new answer"
assert_lacks "$(field 2 witness)" "goodbye" "the other record is untouched"
assert_eq "$(lines)" "2" "no record is lost"
assert_jsonl_valid "and the store is still valid JSONL"
out="$( (cd "$MAIN" && "$SCRIPT" recheck "$first") 2>&1 )"
assert_has "$out" "holds" "the record now holds"
end_sandbox

new_sandbox "rewitness takes an empty answer as the new witness"
record "$MAIN" --check "cat README.md" >/dev/null
: > "$MAIN/README.md"
out="$( (cd "$MAIN" && "$SCRIPT" rewitness "$(field 1 id)") 2>&1 )"
assert_has "$out" "rewitnessed 1" "an empty answer is rewitnessed"
assert_eq "$(field 1 witness)" "" "and becomes the witness"
end_sandbox

new_sandbox "rewitness leaves a record alone when its check cannot run"
record "$MAIN" --check "cat README.md" >/dev/null
before="$(field 1 witness)"
set_fields 1 check "nosuchcmd_318 README.md"
out="$( (cd "$MAIN" && "$SCRIPT" rewitness "$(field 1 id)") 2>&1 )"
assert_has "$out" "skipped" "a check that cannot run is skipped"
assert_has "$out" "nosuchcmd_318" "naming the command"
assert_eq "$(field 1 witness)" "$before" "and the old witness stays"
end_sandbox

new_sandbox "rewitness of an unknown slug changes nothing"
record "$MAIN" >/dev/null
out="$( (cd "$MAIN" && "$SCRIPT" rewitness no-such-slug) 2>&1 )"
assert_eq "$?" 1 "an unknown slug is an error"
assert_eq "$(lines)" "1" "and the store is left as it was"
end_sandbox

new_sandbox "drop clears down the records named and keeps the rest"
record "$MAIN" >/dev/null
record "$MAIN" --claim "docs/commands.md lists no entry for /kit:observe" >/dev/null
record "$MAIN" --claim "CONTEXT.md has no entry for an observation" >/dev/null
gone="$(field 2 id)"
out="$( (cd "$MAIN" && "$SCRIPT" drop "$gone") 2>&1 )"
assert_eq "$?" 0 "the drop succeeds"
assert_eq "$(lines)" "2" "only the named record is removed"
assert_jsonl_valid "and the rewritten store is still valid JSONL"
assert_lacks "$(cat "$STORE")" "lists no entry for /kit:observe" "the dropped claim is gone"
assert_has "$(cat "$STORE")" "Parked list" "the record before it survives"
assert_has "$(cat "$STORE")" "no entry for an observation" "and so does the one after"
end_sandbox

new_sandbox "dropping an unknown slug changes nothing"
record "$MAIN" >/dev/null
out="$( (cd "$MAIN" && "$SCRIPT" drop no-such-slug) 2>&1 )"
assert_eq "$?" 1 "an unknown slug is an error"
assert_eq "$(lines)" "1" "and the store is left as it was"
end_sandbox

# --- summary ------------------------------------------------------------

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
