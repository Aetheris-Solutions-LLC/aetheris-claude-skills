# Comment templates

Read at step 5 of `../SKILL.md`, before posting. Every PR comment body starts
with the `<!-- aetheris-review:v1 -->` marker on its first line; ticket
comments carry it at the end.

Templates are intentionally minimal — narrative tone, not bullet
salad. Keep the templates in sync with the reference skill where the
overlap is direct (link format, sub footer).

## Template — "no issues found"

```markdown
<!-- aetheris-review:v1 -->
### Code review

No issues found. Checked for bugs, CLAUDE.md compliance, regressions
against recent history, prior-PR review comments, and in-code
comment compliance. Grounded against <K> Aetheris ticket(s):
<TICKET-X, TICKET-Y, …>.

🤖 Generated with [Claude Code](https://claude.ai/code)
```

## Template — headline blocker comment

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

## Template — follow-up "before merge" comment

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

## Template — combined "no blockers but worth fixing" comment

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

## Template — per-ticket comment (findings present)

```markdown
Reviewed in PR #<N> ([link to PR comment](<PR comment permalink>)).

Findings attributable to this ticket:

- **Blocker** — <one-liner>. See PR comment for narrative + code link.
- **Before merge** — <one-liner>. See PR comment for narrative + code link.

<!-- aetheris-review:v1 -->
```

## Template — per-ticket comment (no findings)

```markdown
Reviewed in PR #<N> ([link](<PR url>)) — no issues attributable to this ticket.

<!-- aetheris-review:v1 -->
```

## Code-link format (verbatim from reference skill)

GitHub renders markdown link previews only for the canonical
permalink shape. **You must use the full SHA**, not the short SHA,
and not a `$(git rev-parse HEAD)` substitution (the comment renders
as markdown — the substitution never executes):

```
https://github.com/<owner>/<repo>/blob/<full-sha>/<path>#L<start>-L<end>
```

- Use the `head:` SHA from step 0's `pr-facts.sh` output — the commit
  every agent and the Codex lane reviewed.
- Always include at least one line of context before and after the
  flagged line range.
