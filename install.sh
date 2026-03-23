#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/skills/do"
SKILL_DST="$HOME/.claude/skills/do"

if [ ! -d "$SKILL_SRC" ]; then
  echo "Error: skills/do/ not found in $SCRIPT_DIR" >&2
  exit 1
fi

if [ ! -d "$HOME/.claude" ]; then
  echo "Error: ~/.claude/ not found. Is Claude Code installed?" >&2
  echo "Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code" >&2
  exit 1
fi

mkdir -p "$HOME/.claude/skills"

if [ -L "$SKILL_DST" ]; then
  rm "$SKILL_DST"
elif [ -d "$SKILL_DST" ]; then
  echo "Warning: $SKILL_DST is a directory (not a symlink). Backing up to ${SKILL_DST}.bak"
  mv "$SKILL_DST" "${SKILL_DST}.bak"
fi

ln -sfn "$SKILL_SRC" "$SKILL_DST"
echo "Installed: $SKILL_DST -> $SKILL_SRC"
