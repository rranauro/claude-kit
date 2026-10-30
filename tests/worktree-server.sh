#!/usr/bin/env bash
set -uo pipefail

# The worktree server's boot, asserted with curl stubbed on PATH and a fake
# server that records every boot. The trap is a second server: a pass that
# boots without asking whether one already answers leaves two processes fighting
# for one URL, and the one the person sees may be serving the other checkout.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/plugins/kit/scripts/worktree-server.sh"
ORIG_PATH="$PATH"

passed=0
failed=0
current=""

ok()  { echo "  ok   $current — $1"; passed=$((passed + 1)); }
bad() { echo "  FAIL $current — $1" >&2; failed=$((failed + 1)); }

assert_eq() { # actual expected label
  if [ "$1" = "$2" ]; then ok "$3"
  else bad "$3"; diff <(printf '%s\n' "$2") <(printf '%s\n' "$1") | sed 's/^/       /' >&2; fi
}

# A sandbox holds a worktree and two stubs: `curl` answers while $SANDBOX/up
# exists and records each URL it was asked, and `fake-server` appends its cwd
# and argv to $SANDBOX/boots, raises $SANDBOX/up, then stays in the foreground
# the way `bin/rails server` does.
new_sandbox() {
  current="$1"
  echo "==> $current"
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  WT="$SANDBOX/worktree"
  mkdir -p "$SANDBOX/bin"
  git init -q "$WT"
  : > "$SANDBOX/boots"
  export SANDBOX

  cat > "$SANDBOX/bin/curl" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in http*) echo "$a" >> "$SANDBOX/asked" ;; esac; done
[ -e "$SANDBOX/up" ] || exit 7
exit 0
SH
  cat > "$SANDBOX/bin/fake-server" <<'SH'
#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >> "$SANDBOX/boots"
echo "listening"
sleep "${FAKE_DELAY:-0}"
[ "${1:-}" = "--never-answers" ] || : > "$SANDBOX/up"
sleep 30
SH
  chmod +x "$SANDBOX/bin/"*
  export PATH="$SANDBOX/bin:$ORIG_PATH"
}

serve() { # server-line url [extra args] → sets OUT_LINE and CODE
  local line="$1" url="$2"; shift 2
  OUT_LINE="$("$SCRIPT" --server "$line" --url "$url" --remove "just del <branch>" \
    --branch 42-feature --path "$WT" "$@")"
  CODE=$?
}

boots() { grep -c . "$SANDBOX/boots"; }

reap() { pkill -f "$SANDBOX/bin/fake-server" 2>/dev/null; rm -rf "$SANDBOX"; }

new_sandbox "a stopped server is booted and found at its URL"
serve "fake-server" "http://localhost:3000/"
assert_eq "$CODE" 0 "exits 0"
assert_eq "$OUT_LINE" "$(printf 'booted\thttp://localhost:3000/')" "says it booted"
assert_eq "$(boots)" 1 "boots once"
assert_eq "$(cut -d'|' -f1 "$SANDBOX/boots")" "$WT" "runs from the worktree"
assert_eq "$(cut -d'|' -f2 "$SANDBOX/boots")" "" "a line naming no placeholder gets no argument appended"
reap

new_sandbox "a server already answering is not booted again"
: > "$SANDBOX/up"
serve "fake-server" "http://localhost:3000/"
assert_eq "$CODE" 0 "exits 0"
assert_eq "$OUT_LINE" "$(printf 'answering\thttp://localhost:3000/')" "says it already answers"
assert_eq "$(boots)" 0 "boots nothing"
reap

new_sandbox "a second call after a boot finds the first server"
serve "fake-server" "http://localhost:3000/"
serve "fake-server" "http://localhost:3000/"
assert_eq "$OUT_LINE" "$(printf 'answering\thttp://localhost:3000/')" "says it already answers"
assert_eq "$(boots)" 1 "still one boot"
reap

new_sandbox "two overlapping calls boot one server"
export FAKE_DELAY=1
serve "fake-server" "http://localhost:3000/" & first=$!
serve "fake-server" "http://localhost:3000/" & second=$!
wait "$first" "$second"
unset FAKE_DELAY
assert_eq "$(boots)" 1 "boots once"
assert_eq "$([ -e "$(git -C "$WT" rev-parse --absolute-git-dir)/kit-server.lock" ] && echo held || echo released)" \
  "released" "releases the lock"
reap

new_sandbox "a lock nobody released expires"
mkdir "$(git -C "$WT" rev-parse --absolute-git-dir)/kit-server.lock"
serve "fake-server" "http://localhost:3000/" --wait 2
assert_eq "$CODE" 0 "exits 0"
assert_eq "$(boots)" 1 "boots once"
reap

new_sandbox "the boot outlives the call"
serve "fake-server" "http://localhost:3000/"
if pgrep -f "$SANDBOX/bin/fake-server" >/dev/null; then ok "the server is still running"
else bad "the server is still running"; fi
assert_eq "$(cat "$(git -C "$WT" rev-parse --absolute-git-dir)/kit-server.log")" "listening" \
  "its output is logged in the worktree's git directory"
assert_eq "$(git -C "$WT" status --porcelain)" "" "leaves the worktree clean"
reap

new_sandbox "placeholders in both lines are the worktree's"
serve "fake-server --name <branch> --root '<path>'" "http://<branch>.localhost/"
assert_eq "$(cut -d'|' -f2 "$SANDBOX/boots")" "--name 42-feature --root $WT" "the server line gets branch and path"
assert_eq "$(tail -1 "$SANDBOX/asked")" "http://42-feature.localhost/" "the URL gets the branch"
assert_eq "$OUT_LINE" "$(printf 'booted\thttp://42-feature.localhost/')" "reports the resolved URL"
reap

new_sandbox "the line is never run through a shell"
serve "fake-server a && touch $SANDBOX/pwned" "http://localhost:3000/"
assert_eq "$(cut -d'|' -f2 "$SANDBOX/boots")" "a && touch $SANDBOX/pwned" "&& is a literal argument"
assert_eq "$([ -e "$SANDBOX/pwned" ] && echo yes || echo no)" "no" "nothing after && ran"
reap

new_sandbox "a server that never answers is its own failure"
serve "fake-server --never-answers" "http://localhost:3000/" --wait 2
assert_eq "$CODE" 4 "exits 4"
assert_eq "$(printf '%s' "$OUT_LINE" | cut -f1-2)" "$(printf 'not-answering\thttp://localhost:3000/')" "says it did not answer"
assert_eq "$(printf '%s' "$OUT_LINE" | cut -f3)" "$(git -C "$WT" rev-parse --absolute-git-dir)/kit-server.log" "names the log"
reap

new_sandbox "a server command that cannot start is its own failure"
serve "no-such-server-binary" "http://localhost:3000/"
assert_eq "$CODE" 5 "exits 5"
assert_eq "$(printf '%s' "$OUT_LINE" | cut -f1)" "not-started" "says it did not start"
reap

new_sandbox "an unparseable server line is its own failure"
serve "fake-server 'unclosed" "http://localhost:3000/"
assert_eq "$CODE" 5 "exits 5"
assert_eq "$(boots)" 0 "boots nothing"
reap

new_sandbox "a server with no remove declared is never booted"
OUT_LINE="$("$SCRIPT" --server fake-server --url "http://localhost:3000/" --remove "" \
  --branch b --path "$WT")"; CODE=$?
assert_eq "$CODE" 6 "exits 6"
assert_eq "$(printf '%s' "$OUT_LINE" | cut -f1)" "no-remove" "says nothing could stop it"
assert_eq "$(boots)" 0 "boots nothing"
reap

new_sandbox "a missing argument is a usage error"
OUT_LINE="$("$SCRIPT" --server fake-server --branch b --path "$WT" 2>/dev/null)"; CODE=$?
assert_eq "$CODE" 2 "exits 2 without --url"
reap

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
