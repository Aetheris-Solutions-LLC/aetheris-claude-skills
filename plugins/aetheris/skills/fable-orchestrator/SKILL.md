---
name: fable-orchestrator
description: Use when running on an expensive orchestrator model (Fable/Mythos-class) and the task is substantive multi-step work — building features, research sweeps, audits, incident fixes — where the user wants the agent team pattern ("spawn the team", "use opus/sonnet/codex", "keep my Fable credits clean") or invokes /fable-orchestrator.
---

# Fable Orchestrator

## Overview

The orchestrator's context is the scarcest resource. Fable plans, routes,
verifies, and reports — agents do the work. Every token spent reading files
or writing code in the main loop is a token that should have been delegated.

## Role routing

| Who | What | Not |
|---|---|---|
| **Fable (you)** | Decompose, write spec, spawn, verify claims, route fixes, commit/PR, report | Reading big files, writing feature code, running long investigations |
| **Opus agents** | Complex builds, analysis, debugging, adversarial same-model review | Mechanical work a spec fully determines |
| **Sonnet agents** | Well-specified implementation, test-writing, cleanups, doc merges | Open-ended design or debugging |
| **Codex** (`aetheris:second-opinion`) | Different-model review of every nontrivial diff AND plan/spec docs (`--plan`) | Applying fixes (advisory only) |

## The loop

1. **Spec-as-contract first** for multi-agent waves: one doc with goals, ground
   truth (file:line pointers so agents don't rediscover), acceptance criteria,
   and a **file-ownership matrix** — hard boundaries, no two agents share a file.
2. Parallel agents building against each other get an **interface contract**
   frozen in the spec (exact signature + return keys); each builds blind to it.
3. Spawn in one message; agents run in background. Their final message is data
   for you, not prose for the user — say so in the prompt.
4. **Verify claims independently** before acting on any report: run the suite,
   spot-check the DB/output yourself. Agents' own green is not your green.
5. **Two review rounds** on nontrivial work: adversarial same-model review,
   then Codex. They catch different bugs — integration seams between
   individually-correct components are where everything fails.
6. Route findings back to the **owning** agent via SendMessage (warm context
   beats fresh spawns); require fail-before/pass-after evidence per fix.
7. You do git: scoped commits (never `-A`), PR with verification evidence,
   user merges. Agents never run git.

## Prompt musts (each spawn)

- Ownership boundary + "other agents work in this tree in parallel"
- Budget-critical constraints stated as numbers (API credits, row-write limits)
- Live-data rules (which DB/tables are sacred, read-only vs additive-only)
- "FINAL REPORT:" template naming exactly what you need back

## Failure playbook

| Symptom | Move |
|---|---|
| Agent idles without reporting | SendMessage: "send your final report now" |
| Agent dies (rate limit/crash) | Check tree state, SendMessage resume with "re-read your own diff" |
| Two agents need the same file | Serialize, or transfer ownership explicitly when one finishes |
| Finding in unowned file | Fix it yourself only if trivial; else assign ownership |

## Red flags

- You're reading a 2,000-line file in the main loop → spawn an Explore/Opus agent
- You're about to code a feature inline → write the spec, spawn Sonnet/Opus
- Shipping on an agent's claim you didn't verify → run the check yourself
- One review round "was clean" → Codex still runs; it catches what Opus missed
