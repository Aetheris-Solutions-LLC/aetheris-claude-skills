# Tuning and testing

Maintainer notes for `../SKILL.md`: how the tier cutoffs were chosen, when to
move them, and the reference PRs every change is checked against.

## Tuning notes

The cutoffs (90 / 70) were tuned on two reference PRs (see Testing
below). Re-tune if:

- 70 keeps letting in noise → push to 75 (`--before-merge-threshold=75`)
- The follow-up comment is missing real things → drop to 65
- Blocker tier is over-firing → push to 95
- Blocker tier is under-firing → drop to 85

If you tune persistently, edit the defaults in `../SKILL.md` rather than
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

Re-run both with `--dry-run` whenever the models in the plugin's
`MODELS.md` change or the scoring rubric changes — it posts nothing
and doesn't stop on the reference PRs being merged or already
reviewed. If a new run differs and the difference
holds up on inspection, update the expected counts here.
