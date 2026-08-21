---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea, inside a fixed scope. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

## Fence the grilling first

Before round 1, state in one or two sentences what this change builds: from the acceptance criteria if there is a ticket, otherwise from what the user asked for. That statement is the fence. Everything after it is grilling _inside_ the fence.

Anything outside it goes on the **Parked** list. Parking is the default for adjacent work, future work, and anything the user mentioned in passing. A remark about what might matter later is a remark, not a decision to make now; never convert one into a question. Nothing leaves the Parked list without the user asking for it.

Never use `AskUserQuestion` to raise scope. Presenting options turns a non-question into a decision the user is obliged to make. Out-of-scope observations reach the user as a sentence they can ignore.

## Rounds

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled **and whose answer changes what gets built inside the fence**. A question where every possible answer means editing the acceptance criteria is out of frontier by construction; park it. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Format a round like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Scale the grilling to the change. A one-file change does not get four subsystems mapped.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait.

## Stopping

The session is done when no remaining question can change the implementation, **not** when the tree is exhausted. The design tree of any change extends into every adjacent system, so exhausting it is not a reachable stop condition.

Then report the Parked list, unnumbered, as plain observations. Do not act on the design until the user confirms you have reached a shared understanding.
