---
name: second-opinion
description: Use when you want an independent, fresh-perspective code review from a different model (OpenAI Codex) on the current change — a read-only advisory second opinion that never edits code. Triggered by /second-opinion, or when the user asks for "a second opinion", "fresh eyes", or "a Codex review" on a diff, branch, or commit.
argument-hint: "[--uncommitted | --base <branch> | --commit <sha>]"
metadata:
  version: 1.0.0
---

# Second Opinion

Spawn an independent **Codex CLI** review of the current change for a fresh
perspective from a *different model*. Codex advises only — it runs in a
read-only sandbox and **cannot edit code**. Complements your own review or
`/aetheris-review`; it does not replace them.

## When to use

- You want a fresh pair of eyes on a diff before merging — from a model
  other than the one that wrote the code.
- The user asks for "a second opinion", "fresh eyes", or "what would Codex
  say" about a change.
- Before a risky merge, when independent confirmation is worth a pass.

**Not for:** applying fixes (advisory only — acting on a finding is a
separate, explicit step the user must request), or posting PR comments (use
`/aetheris-review`).

## How to run

Run the bundled `review.sh` from this skill's own directory. It selects
scope, invokes Codex read-only, and saves the report **outside** the repo
(`~/.codex-reviews/<repo>/`) so the working tree stays pristine:

```bash
bash <this-skill-dir>/review.sh [scope-flag]
```

Scope — no flag means smart default (on a feature branch → diff vs the
default branch; otherwise the working tree):

| Flag | Reviews |
|---|---|
| _(none)_ | smart default |
| `--uncommitted` | staged + unstaged + untracked |
| `--base <branch>` | diff vs a base branch (PR-equivalent) |
| `--commit <sha>` | a single commit's changes |

The helper streams Codex's review to stdout and ends with a `REPORT_PATH:`
line. (`codex review` cannot combine a scope flag with a custom prompt, so
the skill uses Codex's built-in comprehensive review on the chosen scope.)

## Presenting the result — faithful passthrough

Codex is the advisor. **Do not re-rank, soften, re-judge, or restate its
findings as your own analysis.**

1. Surface Codex's verdict under a clear frame, e.g. *"Codex's independent
   review (read-only):"* and quote its findings as written.
2. Give the saved report path.
3. Close with one line: *"Want me to act on any of these?"*

Acting on a finding (editing code) is a separate step — only after the user
asks. This skill itself never edits code.

## Guarantees

- **No changes:** `--sandbox read-only` makes writes impossible. Confirm with
  `git status` that the repo is untouched after a run.
- **Out-of-repo report:** written to `~/.codex-reviews/<repo>/`, never inside
  the repo.
- **Focused & lean:** runs Codex with `--disable hooks` so the host machine's
  skill/plugin `session_start` hooks aren't injected into the review (without
  it, Codex rabbit-holes reading skill files — ~100x more output). Per-run
  only; your global Codex config is untouched.

## Troubleshooting

- *codex CLI not found* → install (`npm i -g @openai/codex`) or run the
  marketplace's `install-codex.sh`.
- *codex may not be logged in* → `codex login`.
- *no changes to review* → no diff for the chosen scope; pick a different
  scope flag.
