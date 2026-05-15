# aetheris-claude-skills

Curated skills for the Aetheris Solutions workflow, packaged to run
on both **Claude Code** and **Codex CLI**. Currently ships
**`/aetheris-review`**, a multi-agent PR review skill that layers
the Aetheris admin ticket context (project auto-detection,
acceptance-criteria injection, per-ticket comment posting) on top of
the reference `code-review:code-review` fan-out.

The name keeps `claude-skills` for historical reasons — the SKILL.md
format is shared across Claude Code, Codex CLI, and other agent
platforms that follow the [agentskills.io](https://agentskills.io)
spec, so one skill serves both ecosystems.

## Skills in this plugin

| Skill | Invocation | Purpose |
|---|---|---|
| `aetheris-review` | `/aetheris-review` or `/aetheris-review <PR#>` | Multi-agent PR review with Aetheris ticket integration. See [SKILL.md](skills/aetheris-review/SKILL.md) for the full spec. |

More skills will land here as the agency standardises shared
workflows. PRs welcome.

## Install

### Claude Code

```text
/plugin install https://github.com/Aetheris-Solutions-LLC/aetheris-claude-skills
```

Restart Claude Code. Verify by typing `/aetheris-review` — the
slash completion should fire.

Update later:

```text
/plugin update aetheris-claude-skills
```

### Codex CLI

Codex doesn't have a `/plugin install` equivalent — clone the repo
and symlink the skill into `~/.agents/skills/`:

```bash
git clone https://github.com/Aetheris-Solutions-LLC/aetheris-claude-skills \
  ~/.aetheris/aetheris-claude-skills
ln -s ~/.aetheris/aetheris-claude-skills/skills/aetheris-review \
  ~/.agents/skills/aetheris-review
```

Enable multi-agent in `~/.codex/config.toml` (the five-agent fan-out
and per-finding scoring depend on it):

```toml
[features]
multi_agent = true
```

Restart Codex CLI. Update later with
`cd ~/.aetheris/aetheris-claude-skills && git pull`.

See
[`skills/aetheris-review/references/codex-tools.md`](skills/aetheris-review/references/codex-tools.md)
for the full Claude Code → Codex tool mapping and the
`~/.codex/config.toml` MCP wiring.

## Prerequisites

Skills in this plugin assume:

1. **GitHub CLI** — `gh auth status` returns clean.
2. **Aetheris admin MCP** — the `aetheris-admin` MCP server is
   configured and authenticated in your agent's config.
   - Claude Code:
     [docs/admin/claude-code-setup.md](https://github.com/sirzoot/AetherisSite/blob/main/docs/admin/claude-code-setup.md)
   - Codex CLI: see the MCP section of
     [`skills/aetheris-review/references/codex-tools.md`](skills/aetheris-review/references/codex-tools.md)
3. **Sub-agent dispatch capability** — Claude Code's `Agent` tool
   (built-in) or Codex CLI's `spawn_agent` (requires `multi_agent`
   feature flag).

Without the MCP, skills that call `admin_*` tools will fail. The
plugin doesn't ship the MCP server — that lives in
[sirzoot/AetherisSite](https://github.com/sirzoot/AetherisSite) and
is hosted at `https://aetherissolutions.com/admin/mcp`.

## Usage

Once installed, the typical teammate flow:

1. Open your agent inside any Aetheris client repo (AetherisSite,
   footy-access-dev, dripfc, ypi, etc.). The skill auto-detects the
   project by matching the repo URL against `admin.project.list` —
   no need to tell it which client this is.
2. Invoke:
   - On a branch with an open PR: `/aetheris-review`
   - For any other PR: `/aetheris-review 228`
   - With custom thresholds:
     `/aetheris-review 228 --blocker-threshold=85 --before-merge-threshold=65`
   - Skip ack comments on large PRs:
     `/aetheris-review 228 --no-ticket-acks`
3. Wait 2–10 minutes (PR-size dependent). The agent will:
   - Hydrate every referenced Aetheris ticket with its acceptance
     criteria, dependencies, and parent epic.
   - Fan out 5 review agents with ticket context injected into every
     prompt.
   - Score each finding 0–100 with the relevant ticket body as input.
   - Post a tiered PR comment (headline blockers ≥90, follow-up
     before-merge 70–89) and per-ticket findings to Aetheris admin.
4. Look for:
   - One or two new comments on the PR (with the
     `<!-- aetheris-review:v1 -->` marker so re-runs don't dupe).
   - Comments on every touched ticket in the Aetheris admin (look
     for the 🤖 chip).
   - A terminal summary:
     `Reviewed PR #N: K tickets / X blocker / Y before-merge / Z discarded`.

## Development

Clone the repo, then either:

**Option A — symlink into your local skills dir** (fastest iteration):

```bash
git clone https://github.com/Aetheris-Solutions-LLC/aetheris-claude-skills
cd aetheris-claude-skills
# Claude Code:
ln -s "$PWD/skills/aetheris-review" ~/.claude/skills/aetheris-review
# Codex CLI:
ln -s "$PWD/skills/aetheris-review" ~/.agents/skills/aetheris-review
```

Restart your agent. Edits to `skills/aetheris-review/SKILL.md` take
effect on the next session.

**Option B — install as a local plugin** (Claude Code, closer to
how teammates will run it):

```text
/plugin install /absolute/path/to/aetheris-claude-skills
```

## Contributing

- Open a PR against `main` with the skill change.
- Bump the `metadata.version` in `skills/<name>/SKILL.md` for any
  user-visible change.
- Test on **both Claude Code and Codex CLI** if you touch tool-name
  references in the SKILL.md — the mapping in
  `references/codex-tools.md` is the contract.
- The repo follows conventional commits (`feat:`, `fix:`, `docs:`,
  `chore:`).
- For new skills, mirror the layout of `skills/aetheris-review/`
  (a single SKILL.md unless heavy reference material justifies
  splitting — see the
  [superpowers writing-skills guide](https://github.com/anthropics/claude-plugins-official/tree/main/superpowers/skills/writing-skills)
  for conventions).

## License

MIT — see [LICENSE](LICENSE).
