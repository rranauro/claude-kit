#!/usr/bin/env bash
set -uo pipefail

# The kit's default screenshot capture, asserted with Chrome, curl and lsof
# stubbed on PATH. The trap is a screenshot that reads as evidence and is not:
# a page served by some other checkout's server shows the base branch's code,
# so every refusal below has to come back as its own "Not captured" reason
# rather than as an image.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${CAPTURE_PAGE_SCRIPT:-$ROOT/plugins/kit/scripts/capture-page.sh}"
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

# A sandbox holds a worktree, an output directory outside it, and stubs:
# `chrome` writes the file --screenshot names, `curl` answers or refuses by
# $SERVER_UP, and `lsof` reports one listener whose cwd is $SERVER_CWD.
new_sandbox() {
  current="$1"
  echo "==> $current"
  SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
  WT="$SANDBOX/worktree" OUTDIR="$SANDBOX/shots"
  mkdir -p "$SANDBOX/bin" "$WT/public" "$OUTDIR"
  git init -q "$WT"
  echo '<h1>hi</h1>' > "$WT/public/index.html"
  export SERVER_UP=1 SERVER_CWD="$WT" CHROME_WRITES=1 OTHER_CWD="" REDIRECT=""

  cat > "$SANDBOX/bin/chrome" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in --screenshot=*) [ "$CHROME_WRITES" = 1 ] && printf 'PNG' > "${a#--screenshot=}" ;; esac
done
exit 0
SH
  # curl prints $REDIRECT as the redirect_url for the URL asked first, and
  # nothing for any later hop, so a chain is one redirect long.
  cat > "$SANDBOX/bin/curl" <<'SH'
#!/usr/bin/env bash
[ "$SERVER_UP" = 1 ] || exit 7
[ -e "$SANDBOX/.curled" ] || { : > "$SANDBOX/.curled"; printf '%s' "$REDIRECT"; }
exit 0
SH
  # A second listener, pid 4343, appears when $OTHER_CWD is set.
  cat > "$SANDBOX/bin/lsof" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" -t "*) echo 4242; [ -n "$OTHER_CWD" ] && echo 4343 ;;
  *" -p 4343 "*) printf 'p4343\nfcwd\nn%s\n' "$OTHER_CWD" ;;
  *" -d cwd "*) printf 'p4242\nfcwd\nn%s\n' "$SERVER_CWD" ;;
esac
SH
  export SANDBOX
  chmod +x "$SANDBOX/bin/"*
  export KIT_CHROME="$SANDBOX/bin/chrome"
  export PATH="$SANDBOX/bin:$ORIG_PATH"
}

capture() { # url out → sets OUT_LINE and CODE
  OUT_LINE="$(cd "$WT" && "$SCRIPT" "$1" "$2")"
  CODE=$?
}

new_sandbox "a server serving this worktree is captured"
capture "http://localhost:3000/" "$OUTDIR/home.png"
assert_eq "$CODE" 0 "exits 0"
assert_eq "$OUT_LINE" "$OUTDIR/home.png" "prints the image path"
assert_eq "$(cat "$OUTDIR/home.png" 2>/dev/null)" "PNG" "the image is written"

new_sandbox "a server in a subdirectory of the worktree is captured"
mkdir -p "$WT/web"; export SERVER_CWD="$WT/web"
capture "http://127.0.0.1:8080/x" "$OUTDIR/x.png"
assert_eq "$CODE" 0 "exits 0"

new_sandbox "no server answering is its own reason"
export SERVER_UP=0
capture "http://localhost:3000/" "$OUTDIR/home.png"
assert_eq "$CODE" 4 "exits 4"
assert_eq "$OUT_LINE" "Not captured — no server answered at http://localhost:3000/" "says no server answered"
assert_eq "$([ -e "$OUTDIR/home.png" ] && echo yes || echo no)" "no" "writes no image"

new_sandbox "the main checkout's server is refused"
export SERVER_CWD="$SANDBOX/main-checkout"
capture "http://localhost:3000/" "$OUTDIR/home.png"
assert_eq "$CODE" 5 "exits 5"
assert_eq "$OUT_LINE" "Not captured — the server at http://localhost:3000/ is not serving this worktree" "says it is not this worktree's"

new_sandbox "a sibling whose path only starts with the worktree's is refused"
export SERVER_CWD="${WT}-old"
capture "http://localhost:3000/" "$OUTDIR/home.png"
assert_eq "$CODE" 5 "exits 5"

new_sandbox "a second listener on the port from another checkout is refused"
export OTHER_CWD="$SANDBOX/main-checkout"
capture "http://127.0.0.1:3000/" "$OUTDIR/home.png"
assert_eq "$CODE" 5 "exits 5"
assert_eq "$OUT_LINE" "Not captured — the server at http://127.0.0.1:3000/ is not serving this worktree" "says it is not this worktree's"

new_sandbox "a redirect to another origin is refused"
export REDIRECT="http://localhost:4000/"
capture "http://localhost:3000/" "$OUTDIR/home.png"
assert_eq "$CODE" 5 "exits 5"
assert_eq "$OUT_LINE" "Not captured — http://localhost:3000/ redirects to http://localhost:4000/, off the worktree's server" "says where it redirects"

new_sandbox "a redirect on the same origin is followed"
export REDIRECT="http://localhost:3000/sign_in"
capture "http://localhost:3000/" "$OUTDIR/home.png"
assert_eq "$CODE" 0 "exits 0"

new_sandbox "a bracketed IPv6 loopback with no port takes the scheme's port"
capture "http://[::1]/" "$OUTDIR/home.png"
assert_eq "$CODE" 0 "exits 0"

new_sandbox "a remote host cannot be traced to a checkout"
capture "https://staging.example.com/" "$OUTDIR/home.png"
assert_eq "$CODE" 5 "exits 5"
assert_eq "$OUT_LINE" "Not captured — cannot tell which checkout the server at https://staging.example.com/ serves" "says it cannot tell"

new_sandbox "a file inside the worktree needs no server"
export SERVER_UP=0
capture "file://$WT/public/index.html" "$OUTDIR/index.png"
assert_eq "$CODE" 0 "exits 0"
assert_eq "$(cat "$OUTDIR/index.png" 2>/dev/null)" "PNG" "the image is written"

new_sandbox "a file outside the worktree is refused"
echo x > "$SANDBOX/elsewhere.html"
capture "file://$SANDBOX/elsewhere.html" "$OUTDIR/e.png"
assert_eq "$CODE" 5 "exits 5"
assert_eq "$OUT_LINE" "Not captured — file://$SANDBOX/elsewhere.html is not in this worktree" "says it is not in this worktree"

new_sandbox "a symlink in the worktree to a file outside it is refused"
echo x > "$SANDBOX/elsewhere.html"
ln -s "$SANDBOX/elsewhere.html" "$WT/public/linked.html"
capture "file://$WT/public/linked.html" "$OUTDIR/l.png"
assert_eq "$CODE" 5 "exits 5"

new_sandbox "no Chrome on the machine is its own reason"
export KIT_CHROME="$SANDBOX/no-such-chrome"
capture "http://localhost:3000/" "$OUTDIR/home.png"
assert_eq "$CODE" 3 "exits 3"
assert_eq "$OUT_LINE" "Not captured — no headless Chrome on this machine" "says there is no Chrome"

new_sandbox "Chrome writing nothing is its own reason"
export CHROME_WRITES=0
capture "http://localhost:3000/" "$OUTDIR/home.png"
assert_eq "$CODE" 6 "exits 6"
assert_eq "$OUT_LINE" "Not captured — Chrome took no screenshot of http://localhost:3000/" "says Chrome took none"

new_sandbox "an image path inside the worktree is a usage error"
capture "http://localhost:3000/" "$WT/home.png"
assert_eq "$CODE" 2 "exits 2"
assert_eq "$([ -e "$WT/home.png" ] && echo yes || echo no)" "no" "leaves the worktree clean"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
