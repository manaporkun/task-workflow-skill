#!/usr/bin/env bash
# openai-compatible.sh — Calls any OpenAI-compatible API with a prompt file via curl.
# Usage: ./openai-compatible.sh <prompt-file> [model]
# Requires: OPENAI_API_KEY or OPENAI_COMPATIBLE_API_KEY environment variable
#           OPENAI_BASE_URL or OPENAI_COMPATIBLE_BASE_URL for non-OpenAI providers
# Default model: gpt-4o
# Default base URL: https://api.openai.com/v1

set -euo pipefail

PROMPT_FILE="${1:?Usage: openai-compatible.sh <prompt-file> [model]}"
MODEL="${2:-gpt-4o}"

# Support both standard OpenAI and custom env var names
API_KEY="${OPENAI_COMPATIBLE_API_KEY:-${OPENAI_API_KEY:-}}"
BASE_URL="${OPENAI_COMPATIBLE_BASE_URL:-${OPENAI_BASE_URL:-https://api.openai.com/v1}}"

if [ -z "$API_KEY" ]; then
  echo "Error: No API key found. Set OPENAI_API_KEY or OPENAI_COMPATIBLE_API_KEY." >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: Prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

PROMPT_CONTENT=$(cat "$PROMPT_FILE")

# Escape the prompt for JSON embedding
ESCAPED_PROMPT=$(printf '%s' "$PROMPT_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

# Strip trailing slash from base URL
BASE_URL="${BASE_URL%/}"

RESPONSE=$(curl -s -w "\n%{http_code}" \
  --fail-with-body \
  -X POST "${BASE_URL}/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": $ESCAPED_PROMPT}]
  }")

# Split response body and HTTP status code
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ge 400 ] 2>/dev/null; then
  echo "Error: API returned HTTP $HTTP_CODE" >&2
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
    print(f"Error parsing API response: {e}", file=sys.stderr)
    sys.exit(1)
'
