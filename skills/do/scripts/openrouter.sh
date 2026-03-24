#!/usr/bin/env bash
# openrouter.sh — Calls the OpenRouter API with a prompt file via curl.
# Usage: ./openrouter.sh <prompt-file> [model]
# Requires: OPENROUTER_API_KEY environment variable
# Default model: google/gemini-2.0-flash-001

set -euo pipefail

PROMPT_FILE="${1:?Usage: openrouter.sh <prompt-file> [model]}"
MODEL="${2:-google/gemini-3.1-pro-preview}"

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  echo "Error: OPENROUTER_API_KEY environment variable is not set." >&2
  echo "Get your API key at https://openrouter.ai/keys" >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: Prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

PROMPT_CONTENT=$(cat "$PROMPT_FILE")

# Escape the prompt for JSON embedding
ESCAPED_PROMPT=$(printf '%s' "$PROMPT_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

RESPONSE=$(curl -s -w "\n%{http_code}" \
  --fail-with-body \
  -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://github.com/manaporkun/claude-plugins" \
  -H "X-Title: claude-plugins" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": $ESCAPED_PROMPT}]
  }")

# Split response body and HTTP status code
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ge 400 ] 2>/dev/null; then
  echo "Error: OpenRouter API returned HTTP $HTTP_CODE" >&2
  echo "$BODY" >&2
  exit 1
fi

# Extract the assistant's message content
echo "$BODY" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data["choices"][0]["message"]["content"])
except (json.JSONDecodeError, KeyError, IndexError) as e:
    print(f"Error parsing OpenRouter response: {e}", file=sys.stderr)
    sys.exit(1)
'
