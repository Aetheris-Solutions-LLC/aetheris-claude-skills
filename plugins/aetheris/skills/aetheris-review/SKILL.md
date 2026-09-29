---
name: aetheris-review
description: Multi-agent PR review with Aetheris ticket integration. Use when reviewing a PR in any Aetheris client project — auto-detects the project from the repo URL, pulls associated tickets and acceptance criteria into the review, posts a tiered PR comment (blockers + before-merge) and per-ticket findings to Aetheris. Triggered by /aetheris-review or /aetheris-review <PR#>.
argument-hint: "[pr-number] [--blocker-threshold=N] [--before-merge-threshold=N] [--no-ticket-acks] [--codex] [--dry-run]"
---

# Aetheris Review

Multi-agent PR review layered with Aetheris ticket context. Same fan-out
pattern as `code-review:code-review`, but every agent gets the
acceptance criteria for the tickets the PR claims to close, and the
output is tiered — confidence ≥90 lands in a headline blocker
comment, 70–89 lands in a follow-up "rest of the story" comment, and
findings are also posted back to the originating tickets.

## When to use

- The user runs `/aetheris-review` on a branch with an open PR.
- The user runs `/aetheris-review <PR#>` for any PR in any Aetheris
  client project.
- Any time PR review needs to be grounded in the tickets that drove
  the change — not just generic bug scanning.

When **not** to use:

- The PR is in a non-Aetheris repo (no project matches `repo_url`).
  In that case prefer `code-review:code-review` directly.
- The PR is closed, draft, automated, or already has a review comment
  from this skill. Skip silently as the reference skill does.

## Prerequisites

- **GitHub CLI**: `gh auth status` must succeed. Used for everything
  PR-side (view, diff, comment), including `scripts/pr-facts.sh`.
- **Aetheris admin MCP authenticated**. The skill calls the
  `admin_*` tool family. Aetheris team: see the internal (private)
  `AetherisSite` repo, `docs/admin/claude-code-setup.md`,
  for token + JSON config (Claude Code) or
  [`references/codex-tools.md`](references/codex-tools.md) for the
  Codex `~/.codex/config.toml` equivalent.
  Required tools (the `admin_*` names are stable across platforms;
  only the namespace prefix changes — Claude Code uses
  `mcp__aetheris-admin__admin_*`, Codex uses the bare names):
  - Reads: `admin_project_list`, `admin_project_get`,
    `admin_ticket_get`, `admin_ticket_list_comments`,
    `admin_ticket_list_dependencies`, `admin_epic_get`
  - Write: `admin_ticket_post_comment`
- **Sub-agent dispatch** with model selection. On Claude Code that's
  the `Agent` tool with the aliases named in each step (`sonnet` for
  review lanes and scoring, `haiku` for ticket mapping). On Codex CLI
  it's `spawn_agent` — see
  [`references/codex-tools.md`](references/codex-tools.md). The
  plugin's `MODELS.md` maps these roles to current models.
- **Codex CLI** — only for `--codex`. The lane runs the sibling
  `second-opinion` skill's `review.sh`.

Installation: see the marketplace
[README](../../../../README.md#install).

## Arguments

- `<PR#>` (positional, optional) — the PR number to review. If
  omitted, find the open PR for the current branch with
  `gh pr view --json number`. Fail loudly if neither argument nor
  branch PR is present.
- `--blocker-threshold=<N>` (optional, default 90) — score cutoff for
  the headline tier.
- `--before-merge-threshold=<N>` (optional, default 70) — score cutoff
  for the follow-up tier.
- `--no-ticket-acks` (optional) — skip the "Reviewed in PR #N, no
  issues attributable" acknowledgement comments on no-finding tickets.
  Cuts ticket-comment noise when reviewing very large PRs.
- `--codex` (optional) — add a cross-vendor review lane (step 3b)
  whose findings go through the same scoring as the five agents.
- `--dry-run` (optional) — run the whole review but post nothing:
  report eligibility without stopping on it, and print the PR comment
  bodies and per-ticket mapping instead of posting them. Use it to
  re-check the reference PRs in
  [`references/tuning-and-testing.md`](references/tuning-and-testing.md).

Parse these from the slash-command arg string. Anything else after
the PR number that doesn't match a known flag → warn and ignore.

## The flow

Make a todo list before starting. The flow has 8 steps; each is its
own todo so progress is visible.

### Step 0 — Eligibility check

Same conditions as the reference skill: stop if the PR is (a) closed,
(b) a draft, (c) trivial or automated, or (d) already reviewed by this
skill. Run the bundled script with the PR's repository as the working
directory (the script path points into this skill's directory):

```bash
bash <this-skill-dir>/scripts/pr-facts.sh <pr-number>
```

It settles (a), (b), and (d) — (d) by finding the
`<!-- aetheris-review:v1 -->` marker in PR comment bodies — and prints
`eligible: no — <reasons>` or `eligible: yes`. It also prints the
title, author, size, head/base SHAs, base branch, changed files, and
the CLAUDE.md files that govern them; keep that output for the rest of
the flow. Its `head:` SHA is the one commit this review covers — use
it everywhere a SHA is needed (the Codex lane, code links). Decide (c)
yourself from it: a bot author, a lockfile- or version-only diff, and
similar. If any condition holds, stop and report why — or, with
`--dry-run`, note it and continue.

### Step 1 — Project auto-detection

1. `gh repo view --json url,nameWithOwner` → capture both the
   HTTPS URL and the `owner/repo` slug.
2. `admin_project_list` → list every project visible under the
   authenticated MCP token.
3. Match each project's `repo_url` against the PR's repo URL.
   Normalise both sides:
   - strip trailing `.git`
   - strip trailing slash
   - lowercase the host portion
   - also try matching `nameWithOwner` against any project whose
     `repo_url` ends with `/<owner>/<repo>`
4. If exactly one match → bind `project_slug` and `project_name`
   from the matched project. Continue.
5. If zero matches → present the **active** projects
   (`status === 'active'`) and ask the user which one this PR
   belongs to. **Do not proceed without a binding.** If the user
   declines or no active projects exist, fail loudly with a clear
   message.
6. If multiple matches (rare; same repo on two project rows) →
   present both and ask which one to use.

Cache `{project_slug, project_id, project_name, repo_url}` for the
rest of the flow.

### Step 2 — Ticket extraction

Pull the PR body and every commit message on the branch:

```bash
gh pr view <pr> --json body,commits \
  --jq '{body, commits: [.commits[].messageHeadline + "\n" + .commits[].messageBody]}'
```

(Two passes through `.commits[]` is intentional — headline and body
both carry ticket refs.)

Concatenate the body + every commit message into one search corpus,
then extract tickets two ways:

1. **External IDs** — match these regexes against the corpus,
   case-insensitively, and dedupe:
   - `\bTICKET-[A-Z][A-Z0-9]*-[A-Z0-9][A-Z0-9-]*\b` — canonical
     Aetheris external IDs (e.g. `TICKET-PCI-ARC-T01`).
   - After a ref word (`(?:Refs|Ref|Closes|Close|Fixes|Fix|Resolves|Resolve|Aetheris ticket|Ticket)[:\s]+`),
     a token matching `[A-Z][A-Z0-9]*-[A-Z0-9][A-Z0-9-]*` —
     project-specific shorthand like `PCI-OFFERING-X` that doesn't
     have the `TICKET-` prefix.
2. **Bare UUIDs** — after `(?:Aetheris ticket|ticket|Resolves|Closes|Fixes)[:\s]+`,
   a token matching `[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}`
   (case-insensitive). These are direct ticket IDs.

For each candidate:

- External ID → call `admin_ticket_get({ project_slug, external_id })`.
- UUID → call `admin_ticket_get({ id: <uuid> })`.

Some calls will 404 (a string matched the regex but isn't actually a
ticket). Drop those without erroring. Keep only tickets where the
returned `project_id` matches the bound `project_id` — cross-project
matches are a tenant-isolation signal, not a real reference.

For every confirmed ticket also fetch:

- `admin_ticket_list_comments({ id })` — prior review feedback and
  agent comments on this ticket.
- `admin_ticket_list_dependencies({ id })` — related tickets (both
  outgoing and incoming edges).
- If the ticket has `epic_id`, call `admin_epic_get({ id: epic_id })`
  — captures the epic-level "why we're doing this whole arc"
  context. Cache one epic record per epic_id (don't refetch).

Build a **ticket context block** for use later:

```text
### Tickets this PR closes

- TICKET-PCI-ARC-T03 (in_progress) — Build offering arc step renderer
  Acceptance criteria: <body_md, truncated to ~500 chars>
  Skills: [frontend, design]
  Epic: EPIC-PCI-ARC — PCI checkout arc rebuild
  Related: blocks TICKET-PCI-ARC-T05; relates_to TICKET-PCI-ARC-T01

- TICKET-PCI-ARC-T04 (done) — Wire arc step navigation
  …
```

Cache the block in memory and the full per-ticket payloads keyed by
ticket id.

If the corpus contains zero tickets after extraction → continue
anyway, but every later step that depends on ticket context degrades
gracefully (review agents lose the "acceptance criteria" channel,
ticket comments step becomes a no-op). Log a single line in the PR
review comment header noting "No Aetheris tickets referenced in PR
body or commits." so the user can fix the PR description if that
was unintentional.

### Step 3 — Five-agent fan-out (parallel, `model: sonnet`)

Same five agents as the reference skill, dispatched in one message.
Each agent must receive **all four blocks** in its prompt:

1. The PR summary — one line on what this PR does. Write it yourself
   from the title, body, and file list you already have.
2. The `claude_md:` paths from step 0's `pr-facts.sh` output (paths
   only, not contents — the agent reads them as needed).
3. The **ticket context block** from step 2.
4. The project name + repo URL for grounding.

Each agent returns a JSON array of findings: `[{description, why_flagged, file, line_range, evidence}]`.

The five agents:

#### Agent 1 — CLAUDE.md compliance

Audit the diff against every CLAUDE.md the PR touches.

**Important twist not in the reference skill:** if the PR itself
modifies any CLAUDE.md, also check whether the PR's edits to that
CLAUDE.md are accurate against the code in the same PR — i.e. did
the PR change a rule in CLAUDE.md to match code that doesn't
actually follow that rule, or update a path that no longer exists?
That's a "the PR's documentation lied about the code" finding.

Also flag scope violations: if a finding's diff doesn't fall under
any ticket's listed file paths AND introduces behaviour change, that
goes in as a "scope" finding with the relevant CLAUDE.md cited.

#### Agent 2 — Shallow bug scan

Read the diff only (no extra file context beyond the changes
themselves). Focus on large bugs — null derefs, off-by-one, dropped
awaits, security holes — and skip nitpicks. Use the ticket
acceptance criteria to detect "the PR says it satisfies criterion X
but the code clearly doesn't" cases.

#### Agent 3 — Git history / regression detection

Run `git log --oneline`, `git blame`, and `git log -p` against the
modified lines and surrounding area. The headline failure mode this
agent must catch: a bug fix that landed in a recent merged PR and
this PR's rewrite silently re-introduces. To do that:

1. For each file the PR modifies, list the last ~20 commits that
   touched it.
2. For any commit whose subject contains `fix`, `bug`, `regression`,
   or `revert`, pull the diff and check whether the current PR
   undoes that change.
3. Also look for recent PR comments in those commits' merge PRs
   citing the same area.

Output findings in the same JSON shape, with `why_flagged: "regression from #NNN"` where NNN is the PR the original fix shipped in (if known).

#### Agent 4 — Prior PR review comments

For every file the PR modifies, find the previous 3-5 PRs that
touched it (`gh pr list --json number,files,reviewDecision,closedAt --search "<file path>"`).
Read review comments on those PRs and flag anything still applicable.

#### Agent 5 — In-code comment compliance

Read code comments (block + line) in the modified files. Flag where
the PR's changes contradict an explicit comment ("this function
must NOT do X" / "always return a sorted array" / "PRECONDITION:
caller has acquired the lock"). Don't flag where the PR also updated
the comment to match the new behaviour — that's intentional.

**All five agents share the same finding schema** so the next stage
can merge them without type juggling. After fan-out, concatenate the
five JSON arrays into a single `findings[]` list.

### Step 3b — Codex lane (`--codex` only)

A different vendor's model, so different blind spots. Start it before
the fan-out, in the background, and collect it before step 4. It
reviews a detached worktree at the PR head, so your checkout is
untouched:

```bash
TMP="$(mktemp -d)"; WT="$TMP/$(basename "$(git rev-parse --show-toplevel)")"
git worktree add -q --detach "$WT" <head sha>
(cd "$WT" && bash <this-skill-dir>/../second-opinion/review.sh --base <base sha> > /dev/null)
git worktree remove --force "$WT"; rm -rf "$TMP"
```

Both SHAs come from step 0's output, which fetched them; skip the
lane if it printed `commits_local: no`. Stdout goes to `/dev/null`
because it carries Codex's full transcript; the `REPORT_PATH:` line
arrives on stderr. If the run is interrupted, remove the worktree
the same way before retrying. Read the report and convert each Codex
finding into the shared schema with `why_flagged: "Codex second
opinion"`, then append them to `findings[]`. They are scored like
every other finding — don't promote them. If the lane fails (Codex
missing or not logged in), say so in the wrap-up and continue without
it. When this skill itself runs on Codex CLI, the lane is the same
vendor as the fan-out and adds little.

### Step 4 — Confidence scoring (one `model: sonnet` agent per finding)

For each finding, dispatch a scoring agent in parallel. Scoring
decides what gets posted, so it runs on the same tier as the review
lanes. Give the scoring agent:

- The PR summary
- The CLAUDE.md file paths
- **The ticket context block from step 2**
- **The full body_md of any ticket whose file paths overlap with the
  finding's `file`** (so the scorer sees pre-analysed reasoning — the
  "Option A vs Option B" notes that kill false positives that don't
  see ticket context)
- The finding itself

Use the **verbatim** rubric from `code-review:code-review`:

> - **0**: Not confident at all. This is a false positive that
>   doesn't stand up to light scrutiny, or is a pre-existing issue.
> - **25**: Somewhat confident. This might be a real issue, but may
>   also be a false positive. The agent wasn't able to verify that
>   it's a real issue. If the issue is stylistic, it is one that was
>   not explicitly called out in the relevant CLAUDE.md.
> - **50**: Moderately confident. The agent was able to verify this
>   is a real issue, but it might be a nitpick or not happen very
>   often in practice. Relative to the rest of the PR, it's not
>   very important.
> - **75**: Highly confident. The agent double checked the issue,
>   and verified that it is very likely it is a real issue that
>   will be hit in practice. The existing approach in the PR is
>   insufficient. The issue is very important and will directly
>   impact the code's functionality, or it is an issue that is
>   directly mentioned in the relevant CLAUDE.md.
> - **100**: Absolutely certain. The agent double checked the
>   issue, and confirmed that it is definitely a real issue, that
>   will happen frequently in practice. The evidence directly
>   confirms this.

For findings flagged due to CLAUDE.md, the scoring agent must verify
the cited CLAUDE.md actually says what the review agent claimed
(same as the reference skill).

The scoring agent returns `{score: <integer 0–100>, justification: <one sentence>}`.
The five descriptions are calibration anchors, not the only allowed
values: the tier cutoffs in step 5 (90 and 70 by default) sit between
anchors, so a score has to be able to land between them. Score
between two anchors when the evidence sits between their
descriptions.

False-positive examples the agent should treat as score 0 (same as
reference skill plus two additions):

- Pre-existing issues not introduced in this PR
- Things a linter / typechecker / compiler will catch
- Pedantic nitpicks
- General quality issues (test coverage, security hardening) not
  required in CLAUDE.md
- Issues already explicitly silenced in code (lint ignore, etc.)
- Issues on lines the PR didn't actually modify
- **NEW: Issues the relevant ticket explicitly pre-analysed and
  resolved** — e.g. ticket body says "Option B chosen because legacy
  DB rows have null dollar amounts; we backfill at read time" and
  the finding flags "what about null dollar amounts?". Score 0.
- **NEW: Issues that contradict an acceptance criterion** — if the
  finding insists the code should do X but the ticket's acceptance
  criteria explicitly say "do NOT do X", score 0.

### Step 5 — Tier the findings

Sort by score, then assign tiers using the configured thresholds:

- `score >= blocker_threshold` (default 90) → **Blockers**
- `before_merge_threshold <= score < blocker_threshold`
  (default 70–89) → **Before merge**
- `score < before_merge_threshold` → **Discarded**

Re-run the step 0 command (same script path, same PR number) once
before posting, to catch a PR that was closed or already reviewed
during the long fan-out. If its `head:` differs from step 0's, the
author pushed mid-review: say so and stop rather than posting findings
against lines that moved. With `--dry-run`, print the tiers and the
comment bodies below instead of posting, and skip step 6's posts.

Then post comments per this matrix:

| Blockers | Before-merge | What to post |
|---|---|---|
| 0 | 0 | Single "no issues found" comment |
| ≥1 | 0 | Only the headline (blocker) comment |
| ≥1 | ≥1 | Headline comment, then follow-up comment |
| 0 | ≥1 | Single combined comment (see template) |

Use `gh pr comment <pr> --body-file <tmp>` for each comment, with
bodies from
[`references/comment-templates.md`](references/comment-templates.md)
(read it now). Each comment body **must** include the
`<!-- aetheris-review:v1 -->` marker on the first line (so step 0's
"already reviewed" check fires on re-runs). The marker is HTML so it
renders invisibly on GitHub.

### Step 6 — Per-ticket comments

For every ticket in the cache from step 2:

1. **Map findings to the ticket** by:
   - File-path match: any finding whose `file` is listed in the
     ticket's body file pointers (parse them out of the ticket body —
     look for paths matching `frontend/...`, `src/...`,
     `supabase/...`, etc.), OR
   - Acceptance-criteria match: semantically map the finding text to
     the acceptance-criteria bullets. Use a single `model: haiku`
     agent per ticket to do this mapping — give it the finding texts and the
     ticket body, ask for the subset of findings that "directly
     affect whether this ticket's acceptance criteria are met."
2. If the ticket has no attributable findings:
   - Default: post `Reviewed in PR #<N> ([link](<PR url>)) — no
     issues attributable to this ticket. <!-- aetheris-review:v1 -->`
   - Skip this comment if `--no-ticket-acks` was set.
3. If the ticket has ≥1 attributable findings:
   - Post a per-ticket summary listing each finding's tier + short
     description, and link to the PR comment that contains the
     full narrative. Format below.
4. If the ticket's status is `done` AND the PR is **not yet
   merged**, add a warning line: `⚠ This ticket is marked done but
   PR #<N> is still open. Re-open the ticket or merge the PR.`
5. **Unmapped findings** (no ticket file-path or acceptance match)
   → attach them to the parent epic's coordination ticket. Find the
   coordination ticket by listing the epic's tickets and picking
   the one with `external_id` ending in `-T00` or `-COORD` or, if
   neither exists, the lowest-external-id ticket in the epic. If
   the PR has no epic at all (rare), unmapped findings stay only in
   the PR comment.

All posts go through `admin_ticket_post_comment({ id, body })`. The
agent comment will appear in the admin with the 🤖 chip.

### Step 7 — Wrap-up

Print a tight summary to stdout:

```
Reviewed PR #<N> against project <slug>.
  Tickets: <K> matched
  Findings: <X> blocker / <Y> before-merge / <Z> discarded
  Codex lane: <ran / skipped: reason / not requested>
  PR comments posted: <count>
  Ticket comments posted: <count>
```

With `--dry-run`, the last two lines read `0 (dry run)`.

Done.

## Tuning and testing

The 90 / 70 cutoffs, when to move them, and the two reference PRs
every change is checked against:
[`references/tuning-and-testing.md`](references/tuning-and-testing.md).

## Out of scope (v1)

- No build / typecheck / test runs. CI handles those; this skill is
  about review of the diff against ticket intent.
- No auto-status changes on tickets. Findings post as comments only;
  the ticket owner decides whether to re-open / re-claim.
- No support for non-Aetheris repos. If `admin_project_list` returns
  no `repo_url` match and the user can't pick an active project,
  the skill fails loudly rather than silently degrading to plain
  code review.
- No cross-PR memory: a finding flagged on an earlier PR and left
  unaddressed isn't linked back to it.

## Common mistakes

| Mistake | Fix |
|---|---|
| Skipping the eligibility check and posting a duplicate review | Step 0 + the `<!-- aetheris-review:v1 -->` marker exist for this reason. Re-check after the long fan-out (step 5) too. |
| Hardcoding the active project list | Always read it from `admin_project_list` at runtime; the active set changes weekly. |
| Posting per-ticket comments on cross-org matches | Filter by `project_id` after `admin_ticket_get`; a regex match that hits another org's UUID is a security signal, not a match. |
| Code links with the short SHA | They render as plain text on GitHub. Use the full `head:` SHA from step 0. |
| Treating discarded findings (<70) as ignored forever | They're logged in stdout for inspection — useful for tuning thresholds. Don't post them, but don't drop them silently either. |
| Calling `admin_ticket_post_comment` for the PR comment | The PR comment goes through `gh pr comment`, not the Aetheris MCP. The MCP call is for **ticket** comments only. |

## Why this skill exists

`code-review:code-review` is solid for generic PRs, but on the kind
of large epic-driven PRs we ship from this admin board, a single
80-cutoff buries findings that are real-but-not-perfect-confidence,
and it has no way to tell a finding "the ticket already considered
that, score it 0." The tiered output plus ticket-injection
specifically address both gaps. Keep this skill in sync with
`code-review:code-review` for everything that overlaps (link format,
eligibility check, false-positive list) — the differences should
stay narrow and well-justified.
