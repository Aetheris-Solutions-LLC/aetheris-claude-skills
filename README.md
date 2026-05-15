# aetheris-claude-skills

Claude Code skills for the Aetheris Solutions workflow — currently
ships **`/aetheris-review`**, a multi-agent PR review skill that
layers the Aetheris admin ticket context (project auto-detection,
acceptance-criteria injection, per-ticket comment posting) on top of
the reference `code-review:code-review` fan-out.

## Skills in this plugin

| Skill | Invocation | Purpose |
|---|---|---|
| `aetheris-review` | `/aetheris-review` or `/aetheris-review <PR#>` | Multi-agent PR review with ticket integration. See [SKILL.md](skills/aetheris-review/SKILL.md) for the full spec. |

More skills will land here as the agency standardises shared
workflows. PRs welcome.

## Install

In Claude Code:

```text
/plugin install https://github.com/Aetheris-Solutions-LLC/aetheris-claude-skills
```

Restart Claude Code. Verify by typing `/aetheris-review` — the
slash completion should fire.

To update later:

```text
/plugin update aetheris-claude-skills
```

## Prerequisites

Skills in this plugin assume:

1. **GitHub CLI** — `gh auth status` returns clean.
2. **Aetheris admin MCP** — the `aetheris-admin` MCP server is
   configured and authenticated in your Claude Code config. See
   [Aetheris admin setup](https://github.com/sirzoot/AetherisSite/blob/main/docs/admin/claude-code-setup.md)
   in the AetherisSite repo for token + JSON config.

Without the MCP, skills that call `admin_*` tools will fail. The
plugin doesn't ship the MCP server — that lives in
[sirzoot/AetherisSite](https://github.com/sirzoot/AetherisSite) and
is hosted at `https://aetherissolutions.com/admin/mcp`.

## Development

Clone the repo, then either:

**Option A — symlink into your local skills dir** (fastest iteration):

```bash
git clone https://github.com/Aetheris-Solutions-LLC/aetheris-claude-skills
cd aetheris-claude-skills
ln -s "$PWD/skills/aetheris-review" ~/.claude/skills/aetheris-review
```

Restart Claude Code. Edits to `skills/aetheris-review/SKILL.md`
take effect on the next session.

**Option B — install as a local plugin** (closer to how teammates
will run it):

```text
/plugin install /absolute/path/to/aetheris-claude-skills
```

## Contributing

- Open a PR against `main` with the skill change.
- Bump the `metadata.version` in `skills/<name>/SKILL.md` for
  any user-visible change.
- The repo follows conventional commits (`feat:`, `fix:`, `docs:`,
  `chore:`).
- For new skills, mirror the layout of `skills/aetheris-review/`
  (a single SKILL.md unless heavy reference material justifies
  splitting into multiple files — see the
  [superpowers writing-skills guide](https://github.com/anthropics/claude-plugins-official/tree/main/superpowers/skills/writing-skills)
  for conventions).

## License

MIT — see [LICENSE](LICENSE).
