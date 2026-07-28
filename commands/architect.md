---
model: opus
---

Have an architectural discussion about a technical topic, exploring ideas and trade-offs before implementation.

**Topic:** $ARGUMENTS

## Ground Rules

- This is a **conversation**, not a monologue. Ask clarifying questions. Challenge assumptions. Present alternatives.
- Read relevant code and documentation before forming opinions. Don't speculate about how things work — verify.
- Keep responses focused and concise. Prefer bullet points and short paragraphs over walls of text.
- Reference specific files and line numbers when discussing existing code.

## Process

**Phase 1 — Understand the problem space:**
- What is the user trying to achieve? What's the motivation?
- Read relevant code, docs (`THEME_ARCHITECTURE.md`, `DYNAMIC_RENDERING_ARCHITECTURE.md`, `CLAUDE.md`) as needed
- Identify constraints: security, multi-tenancy, performance, Rails conventions
- Ask clarifying questions if the topic is ambiguous

If the topic is "this area feels wrong" rather than a specific change, stop and
offer `/improve-codebase-architecture` instead — a scan-and-report is a better
opening move than reading files ad hoc, and its output feeds back into Phase 2.

**Phase 2 — Explore approaches:**

Start by invoking these two skills, in this order — not as background reading,
as steps:

1. `behavior-placement` — where the behavior belongs (model / value object /
   service) and whether the app already derives the answer. Run both of its
   checks against every approach that adds or moves a class.
2. `codebase-design` — the vocabulary for how deep a module should be
   (interface, seam, depth, leverage). Use these terms exactly when comparing
   approaches; they are the scoring axis, not decoration.

Then:
- Present 2-3 concrete approaches with trade-offs
- For each approach: what changes, what's the blast radius, what are the risks?
- Reference how similar problems are solved elsewhere in the codebase
- Discuss incrementally — don't dump everything at once. Respond to the user's reactions.

**Phase 3 — Converge on a direction:**
- Summarize the agreed approach
- Identify what can be done incrementally vs. what requires a big-bang change
- Flag any open questions that need answers before implementation

Then invoke the `grilling` skill on the converged direction before writing any
tickets. A conversation converges on whatever it drifted toward; grilling is the
adversarial pass that catches the decision nobody actually argued about. Do not
skip it because the direction feels settled — that feeling is the trigger. If
grilling surfaces an unresolved decision, go back to Phase 2 for that branch.

**Phase 4 — Create GitHub issues:**
When the user is ready to move to implementation, invoke the `writing-tickets`
skill and follow it to draft 1 or more issues. It owns the format and the
leanness rules; do not restate them here.

**After each issue is created, ASK whether to write a `plans/<issue-number>-plan.md` now or defer it.** Do not write one automatically.

Write it to the `plans/` directory at the repository root — resolve that with
`git rev-parse --show-toplevel` from the main checkout rather than hardcoding a
path. Add `/plans` to `.gitignore` if it isn't there already: the directory must
stay out of the repo, persist across sessions, and be symlinked into every
worktree by `/start-ticket`. That combination is what makes a plan written here
the durable handoff `/start-ticket` picks up later, even from a fresh worktree.
`mkdir -p` it if it doesn't exist.

Two cases:

- **Defer (default for tickets not being worked on immediately).** The GitHub issue is the durable artifact; `/start-ticket` reads it and re-explores current code. A plan file written now would drift out of sync with the issue and add context noise before the ticket is touched.
- **Write it now (when the ticket will be picked up immediately, or the architectural context is expensive to re-derive).** Capture the durable reasoning that the lean issue intentionally omits — the *why* behind the approach and the alternatives rejected — NOT file lists or line numbers that will rot. Keep it short:

```markdown
# Issue #<number>: <title>

## Context & Motivation
[Why this matters, what prompted it]

## Agreed Approach
[The direction converged on in Phase 3 — intent level]

## Key Decisions & Trade-offs
[Decisions made and why alternatives were rejected — the durable reasoning]
```

Only decisions that were actually examined belong in that last section — in
practice, the ones grilling put pressure on. A mechanism nobody argued about is
an assumption, and writing it beside genuine trade-offs launders it into one:
the implementer can't tell which line cost an hour of discussion and which was
typed in passing. Leave it out. If a substrate really does need naming, mark it
provisional and say what would change it.

If you write one, tell the user it'll be picked up by `/start-ticket`. If deferred, note that the issue alone is the handoff.

## Important

- Do NOT jump to solutions. Explore the problem first.
- Do NOT create issues until the user explicitly says they're ready.
- Do NOT make implementation changes — this is discussion only.
- If the topic is too broad, suggest narrowing scope and ask what to focus on first.
