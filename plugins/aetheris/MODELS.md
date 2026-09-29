# Model routing

The skills in this plugin name **roles**, and use the Claude Code aliases
(`opus`, `sonnet`, `haiku`) that track the current generation. Version-specific
facts — model IDs, prices, and the behaviors the skills' prompts are tuned
against — live here, so a model release is an edit to this file plus the one
default pinned in `skills/second-opinion/review.sh`.

Checked 2026-09-29 against Claude Code 2.1.284 and Codex CLI 0.158.0.

## Roles

| Role | Claude Code | Codex / OpenAI | Used by |
|---|---|---|---|
| Orchestrator | The session model — Fable 5.1 or Opus 5.5 | — | `/fable-orchestrator` |
| Builder | `opus` → Opus 5.5 | — | `/fable-orchestrator` |
| Implementer | `sonnet` → Sonnet 5.5 | — | `/fable-orchestrator` |
| Review lane | `sonnet` → Sonnet 5.5 | `gpt-6-sol` | `/aetheris-review` step 3 |
| Scorer | `sonnet` → Sonnet 5.5 | `gpt-6-sol` | `/aetheris-review` step 4 |
| Triage | `haiku` → Haiku 4.5 | `gpt-6-luna` | `/aetheris-review` step 6 ticket mapping |
| Cross-vendor reviewer | — | `gpt-6-astra` at `high` effort (pinned in `review.sh`; override with `CODEX_REVIEW_MODEL` / `CODEX_REVIEW_EFFORT`) | `/second-opinion`, `/aetheris-review --codex`, `/fable-orchestrator` review round |
| Codex worker | — | `gpt-6-sol` | `/fable-orchestrator` (`codex exec -m`) |

The Codex column is the price-tier analog of the Claude column: Sol sits at
Sonnet's price, Luna below Haiku's.

## Prices (per million tokens, input / output)

| Model | Price | Note |
|---|---|---|
| Claude Fable 5.1 | $10 / $50 | Anthropic's most capable widely released model |
| Claude Opus 5.5 | $4 / $20 | Cheaper than Opus 5 ($5 / $25) |
| Claude Sonnet 5.5 | $2 / $10 | |
| Claude Haiku 4.5 | $1 / $5 | Previous generation; Haiku 5.5 is announced, not shipped |
| GPT-6 Astra | $10 / $50 | OpenAI flagship; Codex's default model in a clean config |
| GPT-6 Sol | $2 / $10 | One tier below Astra (in GPT-5.6, Sol was the top tier) |
| GPT-6 Luna | $0.10 / $0.50 | |

Opus costs 2× Sonnet in this generation. Anthropic's guidance is to try the
stronger model at lower effort before splitting work across models for cost —
one model also keeps one prompt cache. Compare cost per finished task, not per
call.

## Behaviors the prompts are tuned against

- **Opus 5.5** at Claude Code's default `medium` effort matches Opus 5 at `high`
  on agentic coding, with fewer steps. It hands work to subagents readily.
- **Sonnet 5.5** at `low` effort can report a code change done without running
  a check that exercises it. It adds tests and docs nobody asked for, at every
  effort level. At `xhigh` / `max` it starts its own review rounds and may launch
  reviewer subagents. → the spawn contract's evidence, scope, and no-sub-agents
  lines.
- **GPT-6** — OpenAI's GPT-6 prompting guide says to tell the model to bias
  toward action and to say what "done" means, including how much testing.
  Astra specifically follows instructions closely, may stop after a first
  implementation, over-tests small changes, and delegates less than asked;
  OpenAI notes that guidance that helps Sol can over-constrain Astra. → the
  Codex worker prompt in `/fable-orchestrator` (Sol) follows the general
  guide; re-test it on the worker model, not on Astra.

## Effort

- **Claude Code** runs both 5.5 models at `medium` by default. A skill can set
  `effort:` (and `model:`) in its frontmatter. No Agent-tool parameter sets a
  per-subagent effort as of 2.1.284.
- **Codex** takes `-c model_reasoning_effort=<low|medium|high|xhigh|max|ultra>`.
  Codex's catalog defaults Astra to `low` and Sol to `medium`. `ultra` turns
  on proactive subagent delegation — don't use it for `review.sh` or for
  workers bound by a file-ownership matrix.
  `review.sh` pins `high` (override with `CODEX_REVIEW_EFFORT`, e.g. `xhigh`
  for a risky merge) and records what ran in each report. The worker command
  leaves effort to `config.toml` (or the model's default) unless it's passed.

## When a model ships

1. Update the tables above and the check date.
2. Update the `REVIEW_MODEL` and `REVIEW_EFFORT` defaults in
   `skills/second-opinion/review.sh` — the only model settings pinned in code.
3. Run `/doctor prompt-audit` over the plugin and re-test what it flags. The
   spawn contract's "Why these lines" table names the behavior each line
   counters; re-test those against the new model.
4. Re-run `/aetheris-review --dry-run` on its two reference PRs
   (`skills/aetheris-review/references/tuning-and-testing.md`).
5. Bump the plugin version.

## Sources

- Claude models and prices: https://platform.claude.com/docs/en/about-claude/models/overview
- Opus 5.5 prompting: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5
- Sonnet 5.5 prompting: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5
- Claude Code aliases and effort: https://code.claude.com/docs/en/model-config
- GPT-6 models and prices: https://developers.openai.com/api/docs/changelog
- GPT-6 prompting: https://developers.openai.com/api/docs/guides/latest-model
- Codex models: https://developers.openai.com/codex/models
