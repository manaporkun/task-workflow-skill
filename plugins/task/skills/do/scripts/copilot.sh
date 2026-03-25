#!/usr/bin/env bash
# copilot.sh — Calls the GitHub Copilot API with a prompt file via curl.
# Usage: ./copilot.sh <prompt-file> [model]
# Requires: GITHUB_TOKEN or GH_TOKEN environment variable (GitHub PAT with Copilot access)
# Default model: gpt-4o

set -euo pipefail

PROMPT_FILE="${1:?Usage: copilot.sh <prompt-file> [model]}"
MODEL="${2:-gpt-4o}"

# Support both common GitHub token env var names
GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: No GitHub token found. Set GITHUB_TOKEN or GH_TOKEN." >&2
  echo "Your token must belong to an account with an active GitHub Copilot subscription." >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: Prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

# Exchange the GitHub token for a short-lived Copilot session token
SESSION_TOKEN_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/json" \
  "https://api.github.com/copilot_internal/v2/token")

SESSION_HTTP_CODE=$(echo "$SESSION_TOKEN_RESPONSE" | tail -n1)
SESSION_BODY=$(echo "$SESSION_TOKEN_RESPONSE" | sed '$d')

if [ "$SESSION_HTTP_CODE" -ge 400 ] 2>/dev/null; then
  echo "Error: Failed to obtain Copilot session token (HTTP $SESSION_HTTP_CODE)" >&2
  echo "$SESSION_BODY" >&2
  echo "Ensure your GitHub token has Copilot access and the subscription is active." >&2
  exit 1
fi

COPILOT_TOKEN=$(echo "$SESSION_BODY" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data["token"])
except (json.JSONDecodeError, KeyError) as e:
    print(f"Error parsing session token response: {e}", file=sys.stderr)
    sys.exit(1)
')

PROMPT_CONTENT=$(cat "$PROMPT_FILE")

# Escape the prompt for JSON embedding
ESCAPED_PROMPT=$(printf '%s' "$PROMPT_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

RESPONSE=$(curl -s -w "\n%{http_code}" \
  --fail-with-body \
  -X POST "https://api.githubcopilot.com/chat/completions" \
  -H "Authorization: Bearer $COPILOT_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Copilot-Integration-Id: vscode-chat" \
  -H "Editor-Version: vscode/1.85.0" \
  -H "Editor-Plugin-Version: copilot-chat/0.12.0" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": $ESCAPED_PROMPT}]
  }")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ge 400 ] 2>/dev/null; then
  echo "Error: GitHub Copilot API returned HTTP $HTTP_CODE" >&2
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
    print(f"Error parsing Copilot API response: {e}", file=sys.stderr)
    sys.exit(1)
'
