# Spawn contract

Paste into every agent prompt, filled in.

```
You own: <paths>. Do not create, edit, or delete anything outside them —
other agents are working in this tree in parallel.
Do not spawn sub-agents. If this needs a fan-out, stop and report back.
Do not run git.
Build exactly the scope below. If you think the scope is wrong, say so in
your report and build it as specified anyway.
Constraints: <numbers — API credits, row-write caps, rate limits>.
Live data: <which tables are read-only, which are additive-only>.

FINAL REPORT — data for the orchestrator, not prose for a user:
verdict line → files touched → evidence (command + observed result) →
open questions. Under 200 words.
```

## Why these lines

| Line | What it counters |
|---|---|
| No sub-agents | Current Opus delegates readily. An agent you didn't spawn, writing files you didn't assign, voids the ownership matrix |
| Build exactly the scope | It widens scope when the boundary is left implicit |
| Under 200 words | It reports long by default, and every extra word lands in your context |
| No git | Commits are yours. Agents committing mid-wave makes the diff unreviewable |

**Do not add "verify your work."** Current Opus self-verifies natively; the
instruction only buys re-checking you already paid for. Your own independent
check after the report is a trust boundary — that one stays.

## Reviewer prompts

Same contract, one rule inverted: ask for **every** finding with confidence and
severity, then filter yourself. "Only report blockers" gets obeyed literally —
the reviewer finds the bug and drops it before you ever see it.
