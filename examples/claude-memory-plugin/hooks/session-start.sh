#!/usr/bin/env bash
# SessionStart hook: initialize OpenViking memory session + inject relevant memories.
# Uses find() API — OpenViking returns L0 abstracts ranked by relevance.
# For deeper context, use the memory-recall skill mid-session.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [[ ! -f "$OV_CONF" ]]; then
  msg='[openviking-memory] ERROR: ./ov.conf not found (strict mode)'
  json_msg=$(_json_encode_str "$msg")
  echo "{\"systemMessage\": $json_msg}"
  exit 0
fi

OUT="$(run_bridge session-start 2>/dev/null || true)"
OK="$(_json_val "$OUT" "ok" "false")"
STATUS="$(_json_val "$OUT" "status_line" "[openviking-memory] initialization failed")"

# Get server URL from state
SERVER_URL=""
if [[ -f "$STATE_FILE" && -n "$PYTHON_BIN" ]]; then
  SERVER_URL=$("$PYTHON_BIN" -c "import json; print(json.load(open('$STATE_FILE')).get('url',''))" 2>/dev/null || echo "")
fi

ADDL="OpenViking memory is active. For historical context, use the memory-recall skill when needed."

if [[ "$OK" == "true" && -n "$SERVER_URL" ]]; then
  PROJECT_NAME=$(basename "$PROJECT_DIR")
  MEMORIES=$("$PYTHON_BIN" -c "
import json, sys
from urllib import request

server, project = sys.argv[1], sys.argv[2]

def find(query, limit=15):
    try:
        req = request.Request(
            f'{server}/api/v1/search/find',
            data=json.dumps({'query': query, 'limit': limit, 'score_threshold': 0.3}).encode(),
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        with request.urlopen(req, timeout=4) as resp:
            return json.loads(resp.read()).get('result', {}).get('memories', [])
    except Exception:
        return []

results = find(f'user profile preferences patterns decisions {project}')

# Collect abstracts, dedup by text
seen = set()
lines = []
for item in results:
    abstract = (item.get('abstract') or '').strip()
    if not abstract or abstract in seen:
        continue
    # Skip structural descriptions (directory overviews)
    uri = item.get('uri', '')
    if uri.endswith('.overview.md') or uri.endswith('.abstract.md'):
        if '/mem_' not in uri and 'profile' not in uri:
            continue
    seen.add(abstract)
    lines.append(f'- {abstract[:200]}')

if lines:
    print('\n'.join(lines[:15]))
" "$SERVER_URL" "$PROJECT_NAME" 2>/dev/null || echo "")

  if [[ -n "$MEMORIES" ]]; then
    ADDL="IMPORTANT: OpenViking is your memory system. Do NOT use flat-file memory (MEMORY.md or memory/*.md). All memory is managed by OpenViking automatically via session hooks. Use the MCP tools (search, overview, read) for progressive recall when you need historical context.

OpenViking recalled memories:
${MEMORIES}"
  else
    ADDL="IMPORTANT: OpenViking is your memory system. Do NOT use flat-file memory (MEMORY.md or memory/*.md). All memory is managed by OpenViking automatically via session hooks. Use the MCP tools (search, overview, read) for progressive recall when you need historical context."
  fi
fi

json_status=$(_json_encode_str "$STATUS")

if [[ "$OK" == "true" ]]; then
  json_addl=$(_json_encode_str "$ADDL")
  echo "{\"systemMessage\": $json_status, \"hookSpecificOutput\": {\"hookEventName\": \"SessionStart\", \"additionalContext\": $json_addl}}"
  exit 0
fi

echo "{\"systemMessage\": $json_status}"
