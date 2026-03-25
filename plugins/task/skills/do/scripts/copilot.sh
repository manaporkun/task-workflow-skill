#!/usr/bin/env bash
# copilot.sh — Calls the GitHub Copilot CLI with a prompt file.
# Usage: ./copilot.sh <prompt-file> [model]
# Requires: copilot CLI installed and authenticated (run 'copilot login' if needed)

set -euo pipefail

PROMPT_FILE="${1:?Usage: copilot.sh <prompt-file> [model]}"
MODEL="${2:-}"

if ! command -v copilot >/dev/null 2>&1; then
  echo "Error: copilot CLI not found. Install it from https://docs.github.com/copilot/how-tos/copilot-cli" >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: Prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

PROMPT_CONTENT=$(cat "$PROMPT_FILE")

if [ -n "$MODEL" ]; then
  copilot -p "$PROMPT_CONTENT" -s --allow-all-tools --model "$MODEL"
else
  copilot -p "$PROMPT_CONTENT" -s --allow-all-tools
fi
