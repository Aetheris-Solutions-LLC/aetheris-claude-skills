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
Evidence is a check that exercises the change — tests, typecheck, build, or
the changed command — with what it printed. A syntax-only check, or a command
that failed to start, is not evidence; if no real check could run, say which
one and why.
```

## Why these lines

| Line | What it counters |
|---|---|
| No sub-agents | Current Claude models delegate readily — Opus hands work off, and Sonnet at `xhigh`/`max` effort launches its own reviewer sub-agents. An agent you didn't spawn, writing files you didn't assign, voids the ownership matrix |
| Build exactly the scope | Agents widen scope when the boundary is left implicit — Sonnet adds tests and docs nobody asked for |
| Under 200 words | It reports long by default, and every extra word lands in your context |
| No git | Commits are yours. Agents committing mid-wave makes the diff unreviewable |
| Evidence is a real check | At low effort Sonnet can report a change done without running anything that exercises it |

**Do not add a bare "verify your work."** Current Opus checks its own work
unprompted, so the instruction only buys re-checking you already paid for. The
evidence lines ask for the concrete thing instead — which check ran and what it
printed — and that is what catches an agent reporting done without one. Your
own independent check after the report is a trust boundary — that one stays.

The rationale column names the model behavior each line counters. Re-test
those lines when a model ships (checklist in the plugin's `MODELS.md`).

## Reviewer prompts

Same contract, one rule inverted: ask for **every** finding with confidence and
severity, then filter yourself. "Only report blockers" gets obeyed literally —
the reviewer finds the bug and drops it before you ever see it.
