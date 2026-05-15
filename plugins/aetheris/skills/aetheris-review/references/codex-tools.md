# Codex tool mapping for aetheris-review

The `aetheris-review` SKILL.md is written in Claude Code vocabulary
(it talks about `Agent`, `Bash`, the `mcp__aetheris-admin__*` tool
prefix, etc.). On Codex CLI, the skill body works the same — only
the tool names change. Use this table when reading the skill.

## Tool name mapping

| SKILL.md says | Codex equivalent |
|---|---|
| Dispatch an Agent (Sonnet) | `spawn_agent` with your stronger model (e.g. `gpt-5`) |
| Dispatch an Agent (Haiku) | `spawn_agent` with your faster model (e.g. `gpt-5-mini`) |
| Multiple parallel Agent calls | Multiple `spawn_agent` calls in one batch |
| Wait for Agent to return findings | `wait_agent` |
| Free a finished Agent | `close_agent` |
| `TodoWrite` / `TaskCreate` for progress | `update_plan` |
| `Bash` to run `gh`, `git`, etc. | Your native shell tool |
| `Read` / `Write` / `Edit` files | Your native file tools |
| `mcp__aetheris-admin__admin_project_list` | The same MCP tool — Codex namespaces MCP tools differently per platform version; check the tool inventory at session start and adjust the prefix if needed. The underlying `admin_*` names are stable. |

## Prerequisite — enable multi-agent

The five-agent fan-out + one-Haiku-per-finding step require Codex's
multi-agent feature flag. Add to `~/.codex/config.toml`:

```toml
[features]
multi_agent = true
```

Without this, `spawn_agent` is unavailable and the skill cannot
parallelise — you can still run it serially (one review pass at a
time), but expect 4–6× slower wall time on a large PR.

## Model selection

The SKILL.md says "5 parallel Sonnet agents" for review and
"1 Haiku per finding" for scoring. Translate to your Codex model
tiers:

- **Review agents** (the 5 fan-out): use Codex's strongest model
  you have budget for. The Sonnet analog is roughly GPT-5 in 2026
  pricing. Higher reasoning depth = better catches in step 4
  (regressions) and step 5 (in-code comment compliance).
- **Scoring agents** (one per finding): use a faster, cheaper
  model. The Haiku analog is GPT-5-mini or equivalent. The scoring
  rubric is structured enough that smaller models do fine.

You can override these on a per-`spawn_agent` call. The skill body
doesn't lock you into any model — "Sonnet" and "Haiku" are
mnemonic, not normative.

## MCP server setup on Codex

Codex CLI reads MCP servers from `~/.codex/config.toml` under
`[mcp_servers.<name>]`. The Aetheris admin MCP entry mirrors the
Claude Code config in `docs/admin/claude-code-setup.md`:

```toml
[mcp_servers.aetheris-admin]
type = "http"
url = "https://aetherissolutions.com/admin/mcp"
authorization = "Bearer at_live_<your-token>"
```

Restart Codex CLI after editing the config. Verify by asking Codex:
"list the Aetheris admin tools available." You should see
`admin_project_list`, `admin_ticket_get`, etc.

## Slash-command invocation on Codex

Codex CLI auto-discovers skills in `~/.agents/skills/<name>/`.
After installing the plugin (see plugin README for the Codex install
path), the skill activates contextually whenever a PR review task
matches its description, or you can invoke it explicitly with the
slash form your Codex build supports — recent Codex CLI builds
accept `/aetheris-review` and `/aetheris-review 228`.

## Things Codex handles differently

- **Branch / push from sandboxed worktrees.** If you're running
  Codex in an externally-managed worktree (sandboxed), the agent
  may not be able to push or comment via `gh` directly. The skill
  will still post the PR comment if `gh` is auth'd in the sandbox.
  If it isn't, the skill will fail at the comment step — the
  fan-out and scoring still ran, so the findings are visible in
  the agent's output and you can post the comment manually with
  `gh pr comment <pr> --body-file <output>`.
- **Long-running sessions.** Codex idle timeouts differ from Claude
  Code. On very large PRs (93+ files), the full flow can take 8+
  minutes; budget accordingly.

## Anything else?

If you hit a tool-name mismatch the table above doesn't cover, the
SKILL.md is intentionally written in process language, not tool
language — "score each finding 0–100" and "fan out 5 review agents"
read identically on either platform. The mapping above only matters
for the literal tool names; the workflow is the same.
