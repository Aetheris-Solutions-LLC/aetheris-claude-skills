#!/usr/bin/env bash
# install-codex.sh — symlink every skill in this marketplace into
# ~/.agents/skills/ so Codex CLI auto-discovers them.
#
# Idempotent: safe to re-run after `git pull` to pick up new skills.
# Existing symlinks are refreshed; non-symlinks of the same name are
# left alone (so you don't accidentally clobber a teammate's hand-
# rolled skill that shares a name).
#
# Usage:
#   ./install-codex.sh             # symlink every skill in this repo
#   ./install-codex.sh --dry-run   # show what would be linked, don't write
#   ./install-codex.sh --uninstall # remove symlinks pointing back into
#                                   # this repo (leaves other skills alone)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${HOME}/.agents/skills"
DRY_RUN=0
UNINSTALL=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run|--uninstall]"
      exit 0
      ;;
    *)
      echo "Unknown flag: $arg" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$SKILLS_DIR"

# Discover every skill: plugins/*/skills/*/SKILL.md
shopt -s nullglob
declare -a SKILL_PATHS=()
for skill_md in "$REPO_DIR"/plugins/*/skills/*/SKILL.md; do
  SKILL_PATHS+=("$(dirname "$skill_md")")
done

if (( ${#SKILL_PATHS[@]} == 0 )); then
  echo "No SKILL.md found under $REPO_DIR/plugins/*/skills/*/" >&2
  exit 1
fi

installed=0
skipped=0
refreshed=0
removed=0

for skill_dir in "${SKILL_PATHS[@]}"; do
  name="$(basename "$skill_dir")"
  target="$SKILLS_DIR/$name"

  if (( UNINSTALL )); then
    if [[ -L "$target" ]]; then
      link_dest="$(readlink "$target")"
      # Only remove the symlink if it points back into THIS repo —
      # leaves the user's other skills untouched.
      case "$link_dest" in
        "$REPO_DIR"/*)
          if (( DRY_RUN )); then
            echo "would remove: $target -> $link_dest"
          else
            rm "$target"
            echo "removed: $target"
          fi
          removed=$((removed + 1))
          ;;
        *)
          echo "skip ($name): symlink points elsewhere ($link_dest)"
          skipped=$((skipped + 1))
          ;;
      esac
    else
      echo "skip ($name): not a symlink we own"
      skipped=$((skipped + 1))
    fi
    continue
  fi

  if [[ -L "$target" ]]; then
    existing="$(readlink "$target")"
    if [[ "$existing" == "$skill_dir" ]]; then
      echo "ok ($name): already linked"
      skipped=$((skipped + 1))
      continue
    fi
    # Symlink exists but points elsewhere — refresh.
    if (( DRY_RUN )); then
      echo "would refresh: $target ($existing -> $skill_dir)"
    else
      ln -sfn "$skill_dir" "$target"
      echo "refreshed: $name (was $existing)"
    fi
    refreshed=$((refreshed + 1))
    continue
  fi

  if [[ -e "$target" ]]; then
    echo "skip ($name): $target exists and is not a symlink — refusing to clobber"
    skipped=$((skipped + 1))
    continue
  fi

  if (( DRY_RUN )); then
    echo "would link: $target -> $skill_dir"
  else
    ln -s "$skill_dir" "$target"
    echo "linked: $name"
  fi
  installed=$((installed + 1))
done

echo "---"
if (( UNINSTALL )); then
  echo "uninstall summary: removed=$removed skipped=$skipped"
else
  echo "install summary: linked=$installed refreshed=$refreshed skipped=$skipped"
fi

if (( DRY_RUN )); then
  echo "(dry run — no changes written)"
fi
