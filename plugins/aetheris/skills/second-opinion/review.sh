#!/usr/bin/env bash
# review.sh — spawn a read-only Codex CLI "second opinion" review of the
# current change. Codex (a different model) reviews and advises; it CANNOT
# edit (enforced by `--sandbox read-only`). Output is captured to a report
# OUTSIDE the target repo so the repo stays pristine.
#
# Usage:
#   review.sh                 # smart default: feature branch -> diff vs default branch; else --uncommitted
#   review.sh --uncommitted   # staged + unstaged + untracked changes
#   review.sh --base <branch> # diff against a base branch (PR-equivalent)
#   review.sh --commit <sha>  # the changes introduced by one commit
#
# Note: `codex review` forbids combining a scope flag with a custom prompt,
# so we use Codex's built-in comprehensive review on the chosen scope. The
# "fresh perspective" comes from it being a different model; "no changes"
# from the read-only sandbox.
set -uo pipefail

# --- preflight -------------------------------------------------------------
command -v codex >/dev/null 2>&1 || {
  echo "ERROR: codex CLI not found. Install it (e.g. 'npm i -g @openai/codex') or see install-codex.sh." >&2
  exit 3
}
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "ERROR: not inside a git repository — nothing to review." >&2
  exit 3
}
codex login status >/dev/null 2>&1 || \
  echo "WARN: codex may not be logged in. Run 'codex login' if the review fails." >&2

REPO_ROOT="$(git rev-parse --show-toplevel)"
REPO_NAME="$(basename "$REPO_ROOT")"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"

# --- scope selection -------------------------------------------------------
SCOPE_ARGS=()
SCOPE_DESC=""
case "${1:-}" in
  --uncommitted)
    SCOPE_ARGS=(--uncommitted); SCOPE_DESC="uncommitted changes" ;;
  --base)
    [ -n "${2:-}" ] || { echo "ERROR: --base needs a branch name." >&2; exit 2; }
    SCOPE_ARGS=(--base "$2"); SCOPE_DESC="diff vs $2" ;;
  --commit)
    [ -n "${2:-}" ] || { echo "ERROR: --commit needs a SHA." >&2; exit 2; }
    SCOPE_ARGS=(--commit "$2"); SCOPE_DESC="commit $2" ;;
  "")
    # Smart default: on a feature branch with a discoverable default branch,
    # review the branch diff; otherwise review the working tree.
    DEF="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
    if [ -z "$DEF" ]; then
      for b in main master; do
        git show-ref --verify --quiet "refs/heads/$b" && { DEF="$b"; break; }
      done
    fi
    if [ -n "$DEF" ] && [ "$BRANCH" != "$DEF" ] && git rev-parse --verify --quiet "$DEF" >/dev/null; then
      SCOPE_ARGS=(--base "$DEF"); SCOPE_DESC="diff vs $DEF (auto)"
    else
      SCOPE_ARGS=(--uncommitted); SCOPE_DESC="uncommitted changes (auto)"
    fi ;;
  *)
    echo "ERROR: unknown argument '$1'. Use --uncommitted | --base <branch> | --commit <sha>." >&2
    exit 2 ;;
esac

# --- run the review (read-only; Codex cannot write, never prompts) ---------
OUT_DIR="$HOME/.codex-reviews/$REPO_NAME"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y-%m-%d-%H%M%S)"
SAFE_BRANCH="$(printf '%s' "$BRANCH" | tr '/ :' '___')"
REPORT="$OUT_DIR/codex-$STAMP-$SAFE_BRANCH.md"

{
  echo "# Codex second-opinion review — $REPO_NAME"
  echo
  echo "- when: $STAMP"
  echo "- branch: $BRANCH"
  echo "- scope: $SCOPE_DESC"
  echo "- mode: read-only (Codex made no changes)"
  echo
  echo "---"
  echo
} > "$REPORT"

echo "Second opinion (Codex, read-only) · $REPO_NAME · $SCOPE_DESC" >&2
echo >&2

# read-only sandbox = no writes; never-approve = no interactive prompts;
# --disable hooks stops the host machine's session_start hooks from injecting
# skill/plugin machinery (e.g. superpowers) into the review session. Without
# it, Codex rabbit-holes reading skill files — measured ~8300 lines / 140k
# tokens vs ~80 lines with the flag. Per-invocation only; global config is
# untouched.
codex -s read-only -a never --disable hooks review "${SCOPE_ARGS[@]}" 2>&1 | tee -a "$REPORT"
rc=${PIPESTATUS[0]}

echo >&2
echo "REPORT_PATH: $REPORT" >&2
exit "$rc"
