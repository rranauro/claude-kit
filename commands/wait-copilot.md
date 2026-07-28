Poll a PR for GitHub Copilot's review and hand off to `/review-copilot` when comments arrive.

Designed to be run via `/loop` (e.g. `/loop 90s /wait-copilot` or `/loop 90s /wait-copilot 612`). Each firing runs one check; on the firing where Copilot's review has landed, this command notifies the user and chains into `/review-copilot`.

**Step 1 — Resolve the PR:**
- If `$ARGUMENTS` contains a PR number, use it.
- Otherwise run `gh pr view --json number,url,title,headRefName` to get the current branch's PR.
- If no PR is found, print "No PR found for current branch — stopping. Run `/loop stop`." and exit. Do not schedule another check.

**Step 2 — Check for Copilot activity:**
Run both in parallel and capture counts:
```
gh api repos/{owner}/{repo}/pulls/{N}/reviews   --jq '[.[] | select(.user.login | test("copilot"; "i"))] | length'
gh api repos/{owner}/{repo}/pulls/{N}/comments  --jq '[.[] | select(.user.login | test("copilot"; "i"))] | length'
```

`{owner}/{repo}` comes from `gh repo view --json nameWithOwner --jq .nameWithOwner` (run once and reuse).

**Step 3 — Decide:**

**Not ready** (both counts are 0):
- Print one short line: `PR #N: still no Copilot review (checked HH:MM:SS) — next check in ~90s.`
- Do not call any other tools. Do not schedule a wakeup. The `/loop` interval will re-fire.

**Ready** (either count > 0):
1. Fire a macOS notification:
   ```
   osascript -e 'display notification "Copilot review ready for PR #N" with title "Claude Code" subtitle "<repo>" sound name "Glass"'
   ```
2. Print: `Copilot review is in for PR #N. Stop the loop now with /loop stop — I'll start /review-copilot.`
3. Invoke `/review-copilot N` via the Skill tool, passing the PR number explicitly so it doesn't have to re-resolve from the branch.

**Why stop the loop on hit:** `/review-copilot` is interactive (asks you about each comment). If `/loop` fires again mid-review it will interrupt. The "Stop the loop" message is required output — don't omit it.

**Arguments:** `$ARGUMENTS` — optional PR number. If omitted, the current branch's PR is used (and re-resolved on every firing, which is fine).
