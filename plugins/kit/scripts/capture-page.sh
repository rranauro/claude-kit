#!/usr/bin/env bash
set -uo pipefail

# The kit's default screenshot capture for kit:visual-pr: one page, headless
# Chrome, no sign-in. Prints the image path, or one "Not captured — <why>" line
# the PR body takes as written, and exits non-zero.
#
# A script rather than a browser tool named in prose, so the runner's grant can
# name it (ship-settings.json, by the */scripts/ wildcard) and every pass words
# a refusal the same way. The trap it exists for is a screenshot that is not
# evidence: a server already running is usually the main checkout's, and its
# page shows the base branch's code under the branch's caption. So a page is
# taken only when it can be traced to the worktree being shipped — a file in
# it, or a local server whose working directory is in it — and nothing here
# boots a server: that is worktree-server.sh's.
#
# Exit codes: 2 usage, 3 no Chrome, 4 no server answered, 5 not this
# worktree's (or cannot tell), 6 Chrome wrote nothing.

if [ $# -ne 2 ]; then
  echo "usage: capture-page.sh <url> <out.png>   (run from inside the worktree)" >&2
  exit 2
fi
url="$1" out="$2"

worktree="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "capture-page: run it from inside the worktree being shipped" >&2
  exit 2
}
worktree="$(cd "$worktree" && pwd -P)"

# A prefix match alone would take a sibling such as <worktree>-old as inside.
inside() { case "$1/" in "$worktree"/*) return 0 ;; *) return 1 ;; esac; }

# An image left in the worktree reads as uncommitted work and holds it from
# every reclaim.
out_dir="$(cd "$(dirname "$out")" 2>/dev/null && pwd -P)" || {
  echo "capture-page: $(dirname "$out") does not exist" >&2
  exit 2
}
if inside "$out_dir"; then
  echo "capture-page: write the image outside the worktree, not to $out" >&2
  exit 2
fi
out="$out_dir/$(basename "$out")"

not_captured() { echo "Not captured — $2"; exit "$1"; }

# KIT_CHROME, when set, is the only candidate: an operator who named a browser
# did not mean whichever other one happens to be installed.
find_chrome() {
  if [ -n "${KIT_CHROME:-}" ]; then
    [ -x "$KIT_CHROME" ] && echo "$KIT_CHROME"
    return
  fi
  local c
  for c in google-chrome google-chrome-stable chromium chromium-browser; do
    command -v "$c" && return
  done
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
    [ -x "$c" ] && { echo "$c"; return; }
  done
}
chrome="$(find_chrome)"
[ -n "$chrome" ] || not_captured 3 "no headless Chrome on this machine"

# Sets host and port from an http(s) URL; a bracketed IPv6 host has colons of
# its own, so it is split at the bracket rather than the last colon.
origin_of() {
  local hp="${1#*://}"; hp="${hp%%/*}"; hp="${hp##*@}"
  case "$hp" in
    \[*\]:*) host="${hp%:*}" port="${hp##*:}" ;;
    \[*\])   host="$hp" port="" ;;
    *:*)     host="${hp%:*}" port="${hp##*:}" ;;
    *)       host="$hp" port="" ;;
  esac
  [ -n "$port" ] || case "$1" in https://*) port=443 ;; *) port=80 ;; esac
}

case "$url" in
  file://*)
    # Every link is followed before the check, the last one included: a link
    # in the worktree may point at another checkout's page.
    path="${url#file://}"
    while [ -L "$path" ]; do
      target="$(readlink "$path")"
      case "$target" in /*) path="$target" ;; *) path="$(dirname "$path")/$target" ;; esac
    done
    dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)"
    { [ -n "$dir" ] && [ -f "$path" ] && inside "$dir"; } \
      || not_captured 5 "$url is not in this worktree"
    ;;
  http://*|https://*)
    origin_of "$url"
    case "$host" in
      localhost|*.localhost|127.0.0.1|0.0.0.0|\[::1\]) ;;
      *) not_captured 5 "cannot tell which checkout the server at $url serves" ;;
    esac

    # Chrome follows redirects, so every hop has to stay on the origin traced
    # below; a hop off it shows another server's page under this one's caption.
    hop="$url"
    for _ in 1 2 3 4 5; do
      next="$(curl -s -o /dev/null --max-time 10 -w '%{redirect_url}' "$hop" 2>/dev/null)" \
        || not_captured 4 "no server answered at $url"
      [ -n "$next" ] || break
      want="$host:$port"; origin_of "$next"
      [ "$host:$port" = "$want" ] \
        || not_captured 5 "$url redirects to $next, off the worktree's server"
      hop="$next"
    done

    # Every listener on the port must be the worktree's: two servers can bind
    # one port on different addresses, and which one answers is not ours to
    # know.
    pids="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null)"
    [ -n "$pids" ] || not_captured 5 "the server at $url is not serving this worktree"
    for pid in $pids; do
      cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n1)"
      { [ -n "$cwd" ] && inside "$cwd"; } \
        || not_captured 5 "the server at $url is not serving this worktree"
    done
    ;;
  *)
    echo "capture-page: $url is neither an http(s) nor a file:// URL" >&2
    exit 2
    ;;
esac

# Its own profile, so a Chrome the person already has open is neither reused
# nor disturbed.
profile="$(mktemp -d)"
trap 'rm -rf "$profile"' EXIT
rm -f "$out"
"$chrome" --headless --disable-gpu --hide-scrollbars --no-first-run \
  --user-data-dir="$profile" --window-size=1280,900 \
  --screenshot="$out" "$url" >/dev/null 2>&1
[ -s "$out" ] || not_captured 6 "Chrome took no screenshot of $url"
echo "$out"
