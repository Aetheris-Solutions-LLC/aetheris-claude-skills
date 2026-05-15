---
name: aetheris-review
description: Multi-agent PR review with Aetheris ticket integration. Use when reviewing a PR in any Aetheris client project — auto-detects the project from the repo URL, pulls associated tickets and acceptance criteria into the review, posts a tiered PR comment (blockers + before-merge) and per-ticket findings to Aetheris. Triggered by /aetheris-review or /aetheris-review <PR#>.
argument-hint: "[pr-number] [--blocker-threshold=N] [--before-merge-threshold=N] [--no-ticket-acks]"
metadata:
  version: 1.0.0
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
  PR-side (view, diff, comment).
- **Aetheris admin MCP authenticated**. The skill calls the
  `admin_*` tool family. See
  `docs/admin/claude-code-setup.md` in the repo for token setup.
  Required tools (all via `mcp__aetheris-admin__*`):
  - Reads: `admin_project_list`, `admin_project_get`,
    `admin_ticket_get`, `admin_ticket_list_comments`,
    `admin_ticket_list_dependencies`, `admin_epic_get`
  - Write: `admin_ticket_post_comment`
- The skill assumes Sonnet for review agents and Haiku for scoring
  agents (matches `code-review:code-review`). Make these explicit on
  every `Agent` call via the `model` parameter.

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

Parse these from the slash-command arg string. Anything else after
the PR number that doesn't match a known flag → warn and ignore.

## The flow

Make a todo list before starting. The flow has 8 steps; each is its
own todo so progress is visible.

### Step 0 — Eligibility check (Haiku)

Mirrors the reference skill exactly. Dispatch one Haiku agent to ask
whether the PR is (a) closed, (b) a draft, (c) trivial/automated, or
(d) already reviewed by this skill in a prior comment. The
already-reviewed check should look for the marker string
`<!-- aetheris-review:v1 -->` in existing PR comment bodies (we will
embed this marker in our own comments — see Comment templates
below). If any condition is true, stop and report why.

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
gh pr view <pr> --json body,commits,headRefOid,baseRefOid \
  --jq '{body, head: .headRefOid, base: .baseRefOid, commits: [.commits[].messageHeadline + "\n" + .commits[].messageBody]}'
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

### Step 3 — Five-agent fan-out (parallel Sonnet)

Same five agents as the reference skill, dispatched in one message.
Each agent must receive **all four blocks** in its prompt:

1. The PR summary (one-line "what this PR does" generated by a
   Haiku pre-step, same as reference step 3).
2. The list of relevant `CLAUDE.md` paths (also from a Haiku
   pre-step; supply file paths only, not contents — the agent reads
   them as needed).
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

### Step 4 — Confidence scoring (one Haiku per finding)

For each finding, dispatch a Haiku agent in parallel. Give the
scoring agent:

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

The scoring agent returns `{score: 0|25|50|75|100, justification: <one sentence>}`.

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

Re-run the eligibility check from step 0 once before posting (to
catch the case where the PR was closed or already reviewed during
the long fan-out).

Then post comments per this matrix:

| Blockers | Before-merge | What to post |
|---|---|---|
| 0 | 0 | Single "no issues found" comment |
| ≥1 | 0 | Only the headline (blocker) comment |
| ≥1 | ≥1 | Headline comment, then follow-up comment |
| 0 | ≥1 | Single combined comment (see template) |

Use `gh pr comment <pr> --body-file <tmp>` for each comment. Each
comment body **must** include the `<!-- aetheris-review:v1 -->`
marker on the first line (so step 0's "already reviewed" check fires
on re-runs). The marker is HTML so it renders invisibly on GitHub.

### Step 6 — Per-ticket comments

For every ticket in the cache from step 2:

1. **Map findings to the ticket** by:
   - File-path match: any finding whose `file` is listed in the
     ticket's body file pointers (parse them out of the ticket body —
     look for paths matching `frontend/...`, `src/...`,
     `supabase/...`, etc.), OR
   - Acceptance-criteria match: semantically map the finding text to
     the acceptance-criteria bullets. Use a single Haiku agent per
     ticket to do this mapping — give it the finding texts and the
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
  PR comments posted: <count>
  Ticket comments posted: <count>
```

Done.

## Comment templates

Templates are intentionally minimal — narrative tone, not bullet
salad. Keep the templates in sync with the reference skill where the
overlap is direct (link format, sub footer).

### Template — "no issues found"

```markdown
<!-- aetheris-review:v1 -->
### Code review

No issues found. Checked for bugs, CLAUDE.md compliance, regressions
against recent history, prior-PR review comments, and in-code
comment compliance. Grounded against <K> Aetheris ticket(s):
<TICKET-X, TICKET-Y, …>.

🤖 Generated with [Claude Code](https://claude.ai/code)
```

### Template — headline blocker comment

```markdown
<!-- aetheris-review:v1 -->
### Code review

Found <N> issue(s):

1. <brief description> (<why flagged — e.g. "regression from #228",
   "CLAUDE.md says …", "violates acceptance criterion X of
   TICKET-PCI-ARC-T03">)

<full-SHA permalink at PR head, with at least one line of context
above and below, e.g.
https://github.com/<owner>/<repo>/blob/<full-sha>/path/file.ts#L42-L47>

2. <brief description> (<why flagged>)

<full-SHA permalink>

🤖 Generated with [Claude Code](https://claude.ai/code)

<sub>If this code review was useful, please react with 👍. Otherwise, 👎.</sub>
```

### Template — follow-up "before merge" comment

Used when there is at least one blocker AND at least one before-merge
finding. The comment above (the headline) carries the blockers; this
comment carries the rest.

```markdown
<!-- aetheris-review:v1 -->
### Code review — the rest of the story

The comment above flagged the <N> confidence-≥<blocker_threshold>
items. This PR is large and the review surfaced <M> more findings
that landed in the <before_merge_threshold>–<blocker_threshold - 1>
range — not nitpicks, each rated "highly likely to be hit in
practice." Posting them here so the PR reflects the real state of
the change.

**1. <one-line headline> (<TICKET-…>)**

<narrative paragraph: what breaks for the user, the root cause with
a markdown-rendered full-SHA code link, and the fix direction>

**2. <one-line headline> (<TICKET-…>)**

<narrative paragraph>

---

Net: <N> hard blockers + <M> worth fixing before merge. <One closing
sentence on the overall shape — e.g. "Nothing here is structural —
the arc architecture is sound — these are seams where the rewrite
dropped a guarantee the old flow held.">

🤖 Generated with [Claude Code](https://claude.ai/code)
```

### Template — combined "no blockers but worth fixing" comment

Used when there are zero blockers but at least one before-merge
finding.

```markdown
<!-- aetheris-review:v1 -->
### Code review

No hard blockers, but <M> item(s) worth addressing before merge.

**1. <one-line headline> (<TICKET-…>)**

<narrative paragraph with code link>

**2. <one-line headline> (<TICKET-…>)**

<narrative paragraph with code link>

🤖 Generated with [Claude Code](https://claude.ai/code)
```

### Template — per-ticket comment (findings present)

```markdown
Reviewed in PR #<N> ([link to PR comment](<PR comment permalink>)).

Findings attributable to this ticket:

- **Blocker** — <one-liner>. See PR comment for narrative + code link.
- **Before merge** — <one-liner>. See PR comment for narrative + code link.

<!-- aetheris-review:v1 -->
```

### Template — per-ticket comment (no findings)

```markdown
Reviewed in PR #<N> ([link](<PR url>)) — no issues attributable to this ticket.

<!-- aetheris-review:v1 -->
```

### Code-link format (verbatim from reference skill)

GitHub renders markdown link previews only for the canonical
permalink shape. **You must use the full SHA**, not the short SHA,
and not a `$(git rev-parse HEAD)` substitution (the comment renders
as markdown — the substitution never executes):

```
https://github.com/<owner>/<repo>/blob/<full-sha>/<path>#L<start>-L<end>
```

- Get the SHA via `gh pr view <pr> --json headRefOid --jq '.headRefOid'` once,
  cache it for the whole flow.
- Always include at least one line of context before and after the
  flagged line range.

## Tuning notes

The cutoffs (90 / 70) were tuned on two reference PRs (see Testing
below). Re-tune if:

- 70 keeps letting in noise → push to 75 (`--before-merge-threshold=75`)
- The follow-up comment is missing real things → drop to 65
- Blocker tier is over-firing → push to 95
- Blocker tier is under-firing → drop to 85

If you tune persistently, edit the defaults in this file rather than
passing flags every invocation.

## Testing

The skill must produce sensible output on these two reference PRs:

1. **mikerob2/WSV PR #229** (small semantic fix, one ticket UUID in
   the body) — expected: zero items at any tier, single
   "no issues found" comment.
2. **mikerob2/WSV PR #228** (93 files, full epic with
   TICKET-PCI-ARC-T01 through T10) — expected: 2 blockers + 6
   before-merge findings, plus 10 per-ticket comments (one per
   ticket touched).

If a run on either PR produces materially different output than the
hand-run that motivated the skill, something regressed. Investigate
before iterating further.

If `--no-ticket-acks` was passed on the second PR, expect ~3 ticket
comments (only the ones with attributable findings) instead of 10.

## Installation

This skill ships as part of the `aetheris-claude-skills` Claude Code
plugin. Teammates install via:

```bash
/plugin install https://github.com/Aetheris-Solutions-LLC/aetheris-claude-skills
```

Then restart Claude Code. Verify by typing `/aetheris-review` and
checking that the slash completion fires.

To update later, run `/plugin update aetheris-claude-skills` (or
`/plugin uninstall` + reinstall on older Claude Code builds).

For development on the skill itself, clone the plugin repo and
either symlink it into the plugin cache or reinstall from a local
path — see the plugin README for the dev workflow.

After install, restart Claude Code so the skill loader picks it up,
and verify by checking that `Skill aetheris-review` is listed in the
available-skills system reminder, or that `/aetheris-review` is
auto-completable.

## Out of scope (v1)

- No build / typecheck / test runs. CI handles those; this skill is
  about review of the diff against ticket intent.
- No auto-status changes on tickets. Findings post as comments only;
  the ticket owner decides whether to re-open / re-claim.
- No support for non-Aetheris repos. If `admin_project_list` returns
  no `repo_url` match and the user can't pick an active project,
  the skill fails loudly rather than silently degrading to plain
  code review.
- No cross-PR memory (yet). v2 idea: if a finding shows up across
  multiple PRs (e.g. the email-verify-server-side gap shipped in
  #228 keeps reappearing), surface "this was flagged on PR #N and
  not addressed" by reading recent PR comments on the same file.

## Common mistakes

| Mistake | Fix |
|---|---|
| Skipping the eligibility check and posting a duplicate review | Step 0 + the `<!-- aetheris-review:v1 -->` marker exist for this reason. Re-check after the long fan-out (step 5) too. |
| Hardcoding the active project list | Always read it from `admin_project_list` at runtime; the active set changes weekly. |
| Posting per-ticket comments on cross-org matches | Filter by `project_id` after `admin_ticket_get`; a regex match that hits another org's UUID is a security signal, not a match. |
| Code links with the short SHA | They render as plain text on GitHub. Use the full SHA from `headRefOid`. |
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
