#!/usr/bin/env bash
# review.sh — spawn a read-only Codex CLI "second opinion".
#
# Two modes:
#   DIFF (default): Codex reviews a code change (`codex review`).
#   PLAN (--plan):  Codex critiques a plan/spec/design DOC before it is built
#                   (`codex exec`), grounding its critique against the code
#                   the doc references.
#
# Codex (a different model) advises only; it CANNOT edit — enforced by
# `--sandbox read-only`. `--disable hooks` stops the host's skill/plugin
# session_start hooks from bloating the run (~100x). Reports save OUTSIDE the
# repo (`~/.codex-reviews/<repo>/`) so the working tree stays pristine.
#
# Usage:
#   review.sh                  # smart default: feature branch -> vs default branch; else uncommitted
#   review.sh --uncommitted    # staged + unstaged + untracked
#   review.sh --base <branch>  # diff against a base branch (PR-equivalent)
#   review.sh --commit <sha>   # one commit's changes
#   review.sh --plan <file>    # fresh-eyes review of a plan/spec/design doc
set -uo pipefail

# --- preflight (codex always required) -------------------------------------
command -v codex >/dev/null 2>&1 || {
  echo "ERROR: codex CLI not found. Install it (e.g. 'npm i -g @openai/codex') or see install-codex.sh." >&2
  exit 3
}
codex login status >/dev/null 2>&1 || \
  echo "WARN: codex may not be logged in. Run 'codex login' if the review fails." >&2

# Repo context (report naming + diff scope). Optional in --plan mode.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
  IN_REPO=1
else
  REPO_NAME="$(basename "$PWD")"; BRANCH="(no-git)"; IN_REPO=0
fi

# Shared Codex flags: read-only (no writes), never-prompt, no host hooks.
CODEX_FLAGS=(-s read-only -a never --disable hooks)
OUT_DIR="$HOME/.codex-reviews/$REPO_NAME"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y-%m-%d-%H%M%S)"

# run_codex LABEL DESC — runs the CODEX_CMD array, tees to a dated report.
run_codex() {
  local label="$1" desc="$2"
  local report="$OUT_DIR/codex-$STAMP-$label.md"
  {
    echo "# Codex second-opinion — $REPO_NAME"
    echo
    echo "- when: $STAMP"
    echo "- branch: $BRANCH"
    echo "- scope: $desc"
    echo "- mode: read-only (Codex made no changes)"
    echo
    echo "---"
    echo
  } > "$report"
  echo "Second opinion (Codex, read-only) · $REPO_NAME · $desc" >&2
  echo >&2
  # </dev/null: codex exec waits on stdin even when the prompt is in argv;
  # without an EOF (e.g. run in a pipeline/background) it hangs forever.
  "${CODEX_CMD[@]}" </dev/null 2>&1 | tee -a "$report"
  local rc=${PIPESTATUS[0]}
  echo >&2
  echo "REPORT_PATH: $report" >&2
  return "$rc"
}

# Plan-review prompt. The single %s is the doc path.
PLAN_PROMPT='You are a senior engineer giving an INDEPENDENT second opinion on the document at "%s" BEFORE any of it is built or executed. Read it, and read any code or specs it references — you may explore this repository read-only to ground every claim. Review with fresh, skeptical eyes:
1. Soundness — flawed assumptions; anything that will not achieve the stated goal.
2. Sequencing/dependencies — wrong ordering, missing or false dependencies, steps that could be parallelized, anything that risks rework.
3. Risk, cost, reversibility — steps that spend real resources, write production state, or are hard to undo: are they adequately gated, throttled, and reversible? What is the blast radius if a step is wrong?
4. Gaps — missing validation, tests, rollback, or steps; unhandled cases; contradictions between the doc and the referenced code or spec.
Advisory only: do NOT propose patches to apply. Return specific, ranked findings with file:line references (in the doc AND in code). Be a tremendous, concrete advisor.'

# --- mode dispatch ---------------------------------------------------------
case "${1:-}" in
  --plan)
    [ -n "${2:-}" ] || { echo "ERROR: --plan needs a file path." >&2; exit 2; }
    [ -f "$2" ] || { echo "ERROR: plan file not found: $2" >&2; exit 2; }
    # shellcheck disable=SC2059  # PLAN_PROMPT has exactly one %s (the path)
    PROMPT="$(printf "$PLAN_PROMPT" "$2")"
    CODEX_CMD=(codex "${CODEX_FLAGS[@]}" exec "$PROMPT")
    run_codex "plan-$(basename "$2" | tr '/ .:' '____')" "plan review: $2"
    exit $? ;;

  --uncommitted|--base|--commit|"")
    [ "$IN_REPO" -eq 1 ] || { echo "ERROR: diff review needs a git repo (use --plan <file> for a doc)." >&2; exit 3; }
    SCOPE_ARGS=(); SCOPE_DESC=""
    case "${1:-}" in
      --uncommitted) SCOPE_ARGS=(--uncommitted); SCOPE_DESC="uncommitted changes" ;;
      --base) [ -n "${2:-}" ] || { echo "ERROR: --base needs a branch name." >&2; exit 2; }
              SCOPE_ARGS=(--base "$2"); SCOPE_DESC="diff vs $2" ;;
      --commit) [ -n "${2:-}" ] || { echo "ERROR: --commit needs a SHA." >&2; exit 2; }
                SCOPE_ARGS=(--commit "$2"); SCOPE_DESC="commit $2" ;;
      "") DEF="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
          if [ -z "$DEF" ]; then
            for b in main master; do git show-ref --verify --quiet "refs/heads/$b" && { DEF="$b"; break; }; done
          fi
          if [ -n "$DEF" ] && [ "$BRANCH" != "$DEF" ] && git rev-parse --verify --quiet "$DEF" >/dev/null; then
            SCOPE_ARGS=(--base "$DEF"); SCOPE_DESC="diff vs $DEF (auto)"
          else
            SCOPE_ARGS=(--uncommitted); SCOPE_DESC="uncommitted changes (auto)"
          fi ;;
    esac
    CODEX_CMD=(codex "${CODEX_FLAGS[@]}" review "${SCOPE_ARGS[@]}")
    run_codex "$(printf '%s' "$BRANCH" | tr '/ :' '___')" "$SCOPE_DESC"
    exit $? ;;

  *)
    echo "ERROR: unknown argument '$1'. Use --uncommitted | --base <b> | --commit <sha> | --plan <file>." >&2
    exit 2 ;;
esac
