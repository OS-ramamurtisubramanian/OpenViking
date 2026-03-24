#!/usr/bin/env bash
# Stop hook: ingest latest turn into OpenViking session memory.
# After every N turns, async-commit to trigger memory extraction.
# Session stays open — no need to create a new one.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

COMMIT_EVERY="${OV_COMMIT_EVERY:-1}"  # Override via env var; default 1 for testing

STOP_HOOK_ACTIVE="$(_json_val "$INPUT" "stop_hook_active" "false")"
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  echo '{}'
  exit 0
fi

if [[ ! -f "$OV_CONF" || ! -f "$STATE_FILE" ]]; then
  echo '{}'
  exit 0
fi

TRANSCRIPT_PATH="$(_json_val "$INPUT" "transcript_path" "")"
if [[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
  echo '{}'
  exit 0
fi

# 1. Ingest the latest turn
run_bridge ingest-stop --transcript-path "$TRANSCRIPT_PATH" >/dev/null 2>&1 || true

# 2. Periodic async commit on same session
if [[ -f "$STATE_FILE" && -n "$PYTHON_BIN" ]]; then
  INGESTED=$("$PYTHON_BIN" -c "import json; print(json.load(open('$STATE_FILE')).get('ingested_turns',0))" 2>/dev/null || echo "0")
  if [[ "$INGESTED" -gt 0 ]] && (( INGESTED % COMMIT_EVERY == 0 )); then
    SESSION_ID=$("$PYTHON_BIN" -c "import json; print(json.load(open('$STATE_FILE')).get('session_id',''))" 2>/dev/null)
    SERVER_URL=$("$PYTHON_BIN" -c "import json; print(json.load(open('$STATE_FILE')).get('url',''))" 2>/dev/null)

    if [[ -n "$SESSION_ID" && -n "$SERVER_URL" ]]; then
      # Async commit — returns immediately, Haiku extracts in background
      curl -s -X POST "${SERVER_URL}/api/v1/sessions/${SESSION_ID}/commit?wait=false" \
        -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
    fi
  fi
fi

echo '{}'
