---
name: fable-orchestrator
description: Use when running on an expensive orchestrator model (Fable, Mythos, or Opus 5) and the task is substantive parallelizable multi-step work — building features, research sweeps, audits, incident fixes — where the user wants the agent team pattern ("spawn the team", "use opus/sonnet/codex", "orchestrate this", "keep my orchestrator context clean") or invokes /fable-orchestrator. Not for single-file changes or undiagnosed bugs.
---

# Fable Orchestrator

## Overview

The orchestrator's context is the scarcest resource. You plan, route, verify,
and report — agents do the work. Every token spent reading files or writing
code in the main loop is a token that should have been delegated.

## When not to orchestrate

A wave costs a spec, a spawn, two review rounds, and a merge. Below that bar,
orchestrating is slower and more expensive than doing the work.

| Situation | Do instead |
|---|---|
| Change fits in files you can already name | Make the edit. The wave costs more than the work |
| You don't know what's broken yet | Diagnose first — one Explore agent, or read it yourself. A spec needs a diagnosis |
| Each step needs the previous step's output | One agent, or inline. Parallelism was the whole payoff |
| Under ~30 minutes of work | Overhead exceeds the task |

## Prerequisites

`codex` CLI, installed and authenticated on its own OpenAI quota, and the
`aetheris` plugin for `aetheris:second-opinion`. Both the mandatory review round
(loop step 5) and the Codex worker role depend on them — without Codex you have
same-model review only, which is the weaker half.

## Role routing

| Who | What | Not |
|---|---|---|
| **You** — Fable / Mythos / Opus 5 | Decompose, spec, spawn, verify claims, route fixes, git, report | Reading big files, writing feature code, long investigations |
| **Opus** (`model: "opus"`) | Complex builds, analysis, debugging, second-round same-model review | Mechanical work a spec fully determines |
| **Sonnet** (`model: "sonnet"`) | Well-specified implementation, tests, cleanups, doc merges. Sonnet 5 lands near Opus on coding — route volume here | Open-ended design or debugging |
| **Codex reviewer** (`aetheris:second-opinion`) | **Primary** review of every nontrivial diff, and plan/spec docs before build (`--plan <file>`) | Applying its own fixes — advisory only |
| **Codex worker** (`codex exec`) | Tests against Claude-authored code, tie-break patches on disputed findings | Bulk implementation — separate quota, rate-limits under load |

## The spawn contract

Every agent prompt carries the same contract: ownership boundary, no sub-agents,
no git, scope discipline, and a capped FINAL REPORT shape. Copy it from
`spawn-contract.md` in this directory and fill in the brackets.

## Keeping agents off each other's files

| Mechanism | Use when | Cost |
|---|---|---|
| File-ownership matrix in the spec | Work partitions cleanly by path — the common case | Free, but documentation-enforced: one rogue sub-agent voids it |
| `isolation: "worktree"` on the spawn | Writes overlap, or the partition isn't clean | ~200–500ms + disk per agent; you merge the trees back |

## The loop

1. **Spec-as-contract first** for multi-agent waves: goals, ground truth
   (file:line pointers so agents don't rediscover), acceptance criteria, and
   the ownership matrix.
2. Parallel agents building against each other get an **interface contract**
   frozen in the spec (exact signature + return keys); each builds blind to it.
3. Spawn in one message, in background.
4. **Verify claims independently** before acting on any report: run the suite,
   spot-check the DB/output yourself. An agent's own green is not your green —
   this is a trust boundary, and it survives however good the agents get.
5. **Codex reviews first** (`aetheris:second-opinion`) — different model,
   different blind spots, and the load-bearing round now that you and the
   agents are the same model. Then an adversarial same-model pass over the
   post-fix state, where repo context earns its keep. Budget for one round
   only? Run Codex.
6. Route findings back to the **owning** agent via SendMessage (warm context
   beats fresh spawns); require fail-before/pass-after evidence per fix.
7. You do git: scoped commits (never `-A`), PR with verification evidence,
   user merges.

## Codex as a worker

```bash
SCRATCH=$(mktemp -d)
codex exec --sandbox workspace-write --skip-git-repo-check -C <owned-dir> \
  -o "$SCRATCH/report.md" "<task prompt>" < /dev/null > "$SCRATCH/run.log" 2>&1
# report.md is its final message; run.log is the event stream, for when it
# dies and you need to see how far it got.
# `< /dev/null` is load-bearing: codex appends piped stdin to the prompt and
# blocks waiting for EOF. Without it this hangs indefinitely under any tool
# runner that holds stdin open.
```

Its sandbox writes only under `-C` — point it at the owned directory, never
repo root. It has no mailbox, so `-o` is the mailbox: read `report.md`. Best
yield is tests for code a Claude agent wrote, and dueling patches when reviews
disagree — have Codex implement its finding, compare against the Claude
version, pick on evidence.

## Failure playbook

| Symptom | Move |
|---|---|
| Agent idles without reporting | SendMessage: "send your final report now" |
| Agent dies (rate limit/crash) | Check tree state, SendMessage resume with "re-read your own diff" |
| Two agents need the same file | Serialize, or transfer ownership explicitly when one finishes |
| Finding in unowned file | Fix it yourself only if trivial; else assign ownership |
| Report names files you never assigned | It spawned sub-agents — re-derive the diff yourself before trusting any of it |

## Red flags

- Reading a 2,000-line file in the main loop → spawn an Explore/Opus agent
- About to code a feature inline → write the spec, spawn Sonnet/Opus
- Shipping on an agent's claim you didn't verify → run the check yourself
- Skipping Codex because the same-model pass was clean → backwards. Same-model
  shares the author's blind spots; Codex is the round that counts
- You typed "verify your work" into a spawn prompt → delete it
