#!/usr/bin/env bash
# pr-facts.sh — the rule-based half of aetheris-review's eligibility check.
#
# Prints what the skill needs before any agent runs: state, draft, whether this
# skill already reviewed the PR (a comment that opens with its marker), size,
# head/base, the changed files, and the CLAUDE.md files that govern them — then
# an `eligible:` line for the rule-based conditions. Whether the PR is trivial
# or automated is a judgment call left to the model reading this output.
#
# It also makes the PR's head and base commits available locally (fetching
# from origin, then from the PR's own repository for fork checkouts) and says
# whether that worked, for steps that diff or check out the PR.
#
# Usage: pr-facts.sh [pr-number]   # omitted → the open PR for the current branch
# Run from inside the PR's repository. Needs gh (authenticated) and git.
set -uo pipefail

MARKER='<!-- aetheris-review:v1 -->'

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI not found." >&2; exit 3; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "ERROR: run from inside the PR's repository." >&2; exit 3; }

PR="${1:-}"
if [ -z "$PR" ]; then
  PR="$(gh pr view --json number --jq .number 2>/dev/null)" || PR=""
  [ -n "$PR" ] || { echo "ERROR: no PR number given and no open PR for this branch." >&2; exit 2; }
fi

META="$(gh pr view "$PR" \
  --json state,isDraft,author,headRefOid,baseRefOid,baseRefName,additions,deletions,changedFiles,url,title \
  --jq '[.state, .isDraft, .author.login, .headRefOid, .baseRefOid, .baseRefName, .additions, .deletions, .changedFiles, .url, .title] | @tsv')" || {
  echo "ERROR: gh pr view $PR failed." >&2; exit 2; }
IFS=$'\t' read -r STATE DRAFT AUTHOR HEAD BASE BASE_REF ADDS DELS NFILES URL TITLE <<<"$META"

# REST endpoints paginate past the 100-item caps of `gh pr view --json`.
FILES="$(gh api --paginate "repos/{owner}/{repo}/pulls/$PR/files" --jq '.[].filename')" || {
  echo "ERROR: could not list files for PR $PR." >&2; exit 2; }
# Only comments that open with the marker count: the skill's own templates put
# it on the first line, so a comment quoting it mid-text doesn't block a review.
REVIEWED_URLS="$(gh api --paginate "repos/{owner}/{repo}/issues/$PR/comments" \
  --jq '.[] | select(.body | test("^\\s*<!-- aetheris-review:v1 -->")) | .html_url')" || {
  echo "ERROR: could not read comments on PR $PR." >&2; exit 2; }

have() { git cat-file -e "$1^{commit}" 2>/dev/null; }
for remote in origin "${URL%/pull/*}"; do
  have "$HEAD" || git fetch -q "$remote" "pull/$PR/head" 2>/dev/null
  have "$BASE" || git fetch -q "$remote" "$BASE_REF" 2>/dev/null
  have "$HEAD" && have "$BASE" && break
done
if have "$HEAD" && have "$BASE"; then LOCAL=yes; else LOCAL=no; fi

# CLAUDE.md files at the PR head in the repo root or an ancestor directory of a
# changed path. Read from local git when the head is here, else from the API.
ANCESTORS="$(printf '%s\n' "$FILES" | awk -F/ 'NF {
    print "."; p = ""
    for (i = 1; i < NF; i++) { p = (p == "" ? $i : p "/" $i); print p }
  }' | sort -u)"
if have "$HEAD"; then
  CLAUDE_MD="$(git -c core.quotePath=false ls-tree -r --name-only "$HEAD" |
    grep -E '(^|/)CLAUDE\.md$' |
    while IFS= read -r c; do
      d="${c%/CLAUDE.md}"; [ "$d" = "$c" ] && d="."
      grep -qxF "$d" <<<"$ANCESTORS" && echo "$c"
    done)"
else
  CLAUDE_MD="$(while IFS= read -r d; do
      [ -n "$d" ] || continue
      p="CLAUDE.md"; [ "$d" = "." ] || p="$d/CLAUDE.md"
      gh api --silent "repos/{owner}/{repo}/contents/$p?ref=$HEAD" 2>/dev/null && echo "$p"
    done <<<"$ANCESTORS")"
fi

reasons=()
[ "$STATE" = "OPEN" ] || reasons+=("state is $STATE")
[ "$DRAFT" = "true" ] && reasons+=("draft")
[ -n "$REVIEWED_URLS" ] && reasons+=("already reviewed")

echo "pr: $PR ($URL)"
echo "title: $TITLE"
echo "author: $AUTHOR"
echo "state: $STATE"
echo "draft: $DRAFT"
if [ -n "$REVIEWED_URLS" ]; then
  echo "already_reviewed: true — comments opening with $MARKER:"
  printf '%s\n' "$REVIEWED_URLS" | sed 's/^/  /'
else
  echo "already_reviewed: false"
fi
echo "size: $NFILES files, +$ADDS/-$DELS"
echo "head: $HEAD"
echo "base: $BASE ($BASE_REF)"
echo "commits_local: $LOCAL"
echo "claude_md:"
printf '%s\n' "$CLAUDE_MD" | sed '/^$/d; s/^/  /'
echo "files:"
printf '%s\n' "$FILES" | sed '/^$/d; s/^/  /'
if [ ${#reasons[@]} -eq 0 ]; then
  echo "eligible: yes"
else
  joined="$(printf '%s; ' "${reasons[@]}")"
  echo "eligible: no — ${joined%; }"
fi
