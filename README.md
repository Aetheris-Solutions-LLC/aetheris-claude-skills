# aetheris-claude-skills

A **Claude Code marketplace** of curated skills for the Aetheris
Solutions agency workflow. Currently ships one plugin (`aetheris`)
with two skills (`/aetheris-review` and `/second-opinion`); grows as
the team standardises shared workflows. The same SKILL.md sources also work on **Codex
CLI** — see the Codex install section below.

## What's in here

| Plugin | Skills | What it does |
|---|---|---|
| `aetheris` | `/aetheris-review` | Multi-agent PR review with Aetheris admin ticket integration. Auto-detects the project, hydrates ticket acceptance criteria, fans out 5 review agents (CLAUDE.md / shallow bug / git regression / prior PR comments / in-code comment compliance), scores each finding 0–100, posts tiered PR comments (blockers ≥90, before-merge 70–89), and posts per-ticket findings back to Aetheris. Full spec: [SKILL.md](plugins/aetheris/skills/aetheris-review/SKILL.md). |
| `aetheris` | `/second-opinion` | Independent, read-only Codex CLI review for a fresh perspective from a different model — on a code change (`--uncommitted` / `--base` / `--commit`, smart default) or a plan/spec/design doc before it's built (`--plan <file>`). Advisory only, never edits; runs Codex in a read-only sandbox with host skill-hooks disabled; report saved outside the repo (`~/.codex-reviews/`). Full spec: [SKILL.md](plugins/aetheris/skills/second-opinion/SKILL.md). |

## Install

### Claude Code (recommended)

Two commands — first register this repo as a marketplace, then
install the plugin from it:

```text
/plugin marketplace add Aetheris-Solutions-LLC/aetheris-claude-skills
/plugin install aetheris@aetheris-claude-skills
```

Restart Claude Code. Verify with `/aetheris-review` — the slash
completion should fire, and `aetheris` should be listed under
`/plugin` ▸ Installed.

Update later:

```text
/plugin update aetheris@aetheris-claude-skills
```

When new skills land in the `aetheris` plugin, `/plugin update`
picks them up automatically — no per-skill action needed.

### Codex CLI

Codex doesn't have a marketplace concept yet — clone the repo and
run the included script to symlink every skill into
`~/.agents/skills/`:

```bash
git clone https://github.com/Aetheris-Solutions-LLC/aetheris-claude-skills \
  ~/.aetheris/aetheris-claude-skills
~/.aetheris/aetheris-claude-skills/install-codex.sh
```

Enable multi-agent in `~/.codex/config.toml` (the five-agent fan-out
and per-finding scoring depend on it):

```toml
[features]
multi_agent = true
```

Restart Codex CLI. Update later — same one-liner picks up any new
skills added to the marketplace:

```bash
cd ~/.aetheris/aetheris-claude-skills && git pull && ./install-codex.sh
```

The script is idempotent (re-run safely), refreshes stale symlinks,
and supports `--dry-run` and `--uninstall` flags.

See [`plugins/aetheris/skills/aetheris-review/references/codex-tools.md`](plugins/aetheris/skills/aetheris-review/references/codex-tools.md)
for the Claude Code → Codex tool mapping (`Agent` → `spawn_agent`,
TodoWrite → `update_plan`, etc.) and the parallel
`~/.codex/config.toml` MCP wiring example.

## Prerequisites

Skills in this marketplace assume:

1. **GitHub CLI** — `gh auth status` returns clean.
2. **Aetheris admin MCP** — the `aetheris-admin` MCP server is
   configured and authenticated in your agent's config.
   - Claude Code:
     [docs/admin/claude-code-setup.md](https://github.com/sirzoot/AetherisSite/blob/main/docs/admin/claude-code-setup.md)
   - Codex CLI: see the MCP section of
     [`plugins/aetheris/skills/aetheris-review/references/codex-tools.md`](plugins/aetheris/skills/aetheris-review/references/codex-tools.md)
3. **Sub-agent dispatch capability** — Claude Code's `Agent` tool
   (built-in) or Codex CLI's `spawn_agent` (requires
   `multi_agent = true`).

Without the MCP, skills that call `admin_*` tools will fail. The
plugin doesn't ship the MCP server — that lives in
[sirzoot/AetherisSite](https://github.com/sirzoot/AetherisSite) and
is hosted at `https://aetherissolutions.com/admin/mcp`.

## Usage

Once installed, the typical flow:

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
3. Wait 2–10 minutes (PR-size dependent). The agent will hydrate
   tickets, fan out review agents with ticket context injected,
   score findings, and post comments.
4. Look for:
   - One or two new comments on the PR (with the
     `<!-- aetheris-review:v1 -->` marker so re-runs don't dupe).
   - Comments on every touched ticket in the Aetheris admin (look
     for the 🤖 chip).
   - A terminal summary:
     `Reviewed PR #N: K tickets / X blocker / Y before-merge / Z discarded`.

## Repo structure

```
aetheris-claude-skills/                 ← this repo (the marketplace)
├── .claude-plugin/marketplace.json     ← marketplace manifest
├── install-codex.sh                    ← symlink every skill into ~/.agents/skills/
├── plugins/
│   └── aetheris/                       ← the plugin
│       ├── .claude-plugin/plugin.json  ← plugin manifest
│       └── skills/
│           ├── aetheris-review/        ← multi-agent PR review
│           │   ├── SKILL.md
│           │   └── references/
│           │       └── codex-tools.md
│           └── second-opinion/         ← read-only Codex fresh-eyes review
│               ├── SKILL.md
│               └── review.sh
├── README.md                           ← you are here
└── LICENSE
```

Adding a new skill: drop another directory under
`plugins/aetheris/skills/<name>/` with its own `SKILL.md`. The
plugin auto-discovers it; teammates pick it up on next
`/plugin update aetheris@aetheris-claude-skills` (Claude Code) or
`git pull && ./install-codex.sh` (Codex CLI).

Adding a new plugin: drop another directory under `plugins/<name>/`
with its own `.claude-plugin/plugin.json` and `skills/` tree, then
add an entry to `.claude-plugin/marketplace.json` under `plugins[]`
pointing at `./plugins/<name>`.

## Development

Clone the repo, then either:

**Option A — symlink into your local skills dir** (fastest iteration):

```bash
git clone https://github.com/Aetheris-Solutions-LLC/aetheris-claude-skills
cd aetheris-claude-skills
# Claude Code:
ln -s "$PWD/plugins/aetheris/skills/aetheris-review" \
      ~/.claude/skills/aetheris-review
# Codex CLI:
./install-codex.sh
```

Restart your agent. Edits to the SKILL.md take effect on the next
session.

**Option B — install as a local marketplace** (closer to teammate
experience):

```text
/plugin marketplace add /absolute/path/to/aetheris-claude-skills
/plugin install aetheris@aetheris-claude-skills
```

## Contributing

- Open a PR against `main` with the skill change.
- Bump `metadata.version` on any modified SKILL.md AND the
  `version` field in `plugins/<plugin>/.claude-plugin/plugin.json`
  for user-visible changes so `/plugin update` flags an upgrade.
- The repo follows conventional commits (`feat:`, `fix:`, `docs:`,
  `chore:`).
- Test on **both Claude Code and Codex CLI** if you touch tool-name
  references in any SKILL.md — `references/codex-tools.md` is the
  contract.
- For new skills, mirror the layout of `aetheris-review/` (a single
  SKILL.md unless heavy reference material justifies splitting —
  see the [superpowers writing-skills guide](https://github.com/anthropics/claude-plugins-official/tree/main/superpowers/skills/writing-skills)
  for conventions).

## License

MIT — see [LICENSE](LICENSE).
