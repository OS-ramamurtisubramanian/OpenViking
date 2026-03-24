#!/usr/bin/env bash
# SessionEnd hook: async-commit OpenViking session to extract long-term memories.
# Uses wait=false so the hook returns immediately — extraction happens in background.
# Cleans up per-session state file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [[ ! -f "$OV_CONF" || ! -f "$STATE_FILE" ]]; then
  exit 0
fi

if [[ -n "$PYTHON_BIN" && -f "$STATE_FILE" ]]; then
  SESSION_ID=$("$PYTHON_BIN" -c "import json; print(json.load(open('$STATE_FILE')).get('session_id',''))" 2>/dev/null)
  SERVER_URL=$("$PYTHON_BIN" -c "import json; print(json.load(open('$STATE_FILE')).get('url',''))" 2>/dev/null)

  if [[ -n "$SESSION_ID" && -n "$SERVER_URL" ]]; then
    # Async commit — returns immediately, Haiku extracts in background
    curl -s -X POST "${SERVER_URL}/api/v1/sessions/${SESSION_ID}/commit?wait=false" \
      -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true

    # Clean up per-session state file
    rm -f "$STATE_FILE"

    json_status=$(_json_encode_str "[openviking-memory] session committed (async) id=${SESSION_ID}")
    echo "{\"systemMessage\": $json_status}"
    exit 0
  fi
fi

exit 0
