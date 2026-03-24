#!/usr/bin/env bash
# SubagentStart hook: inject L0 memories into subagent context.
# Subagents inherit MCP tools but don't get SessionStart injection.
# This gives them historical context to avoid mistakes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [[ ! -f "$OV_CONF" ]]; then
  echo '{}'
  exit 0
fi

# Get server URL from parent session's state file
SERVER_URL=""
if [[ -f "$STATE_FILE" && -n "$PYTHON_BIN" ]]; then
  SERVER_URL=$("$PYTHON_BIN" -c "import json; print(json.load(open('$STATE_FILE')).get('url',''))" 2>/dev/null || echo "")
fi

# Fallback: try the ov.conf server config directly
if [[ -z "$SERVER_URL" && -n "$PYTHON_BIN" ]]; then
  SERVER_URL=$("$PYTHON_BIN" -c "
import json
conf = json.load(open('$OV_CONF'))
s = conf.get('server', {})
host = s.get('host', '127.0.0.1')
port = s.get('port', 1933)
print(f'http://{host}:{port}')
" 2>/dev/null || echo "http://127.0.0.1:1933")
fi

if [[ -z "$SERVER_URL" ]]; then
  echo '{}'
  exit 0
fi

PROJECT_NAME=$(basename "$PROJECT_DIR")
MEMORIES=$("$PYTHON_BIN" -c "
import json, sys
from urllib import request

server, project = sys.argv[1], sys.argv[2]

def find(query, limit=10):
    try:
        req = request.Request(
            f'{server}/api/v1/search/find',
            data=json.dumps({'query': query, 'limit': limit, 'score_threshold': 0.3}).encode(),
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        with request.urlopen(req, timeout=3) as resp:
            return json.loads(resp.read()).get('result', {}).get('memories', [])
    except Exception:
        return []

results = find(f'user profile preferences patterns decisions {project}')

seen = set()
lines = []
for item in results:
    abstract = (item.get('abstract') or '').strip()
    if not abstract or abstract in seen:
        continue
    uri = item.get('uri', '')
    if uri.endswith('.overview.md') or uri.endswith('.abstract.md'):
        if '/mem_' not in uri and 'profile' not in uri:
            continue
    seen.add(abstract)
    lines.append(f'- {abstract[:200]}')

if lines:
    print('\n'.join(lines[:10]))
" "$SERVER_URL" "$PROJECT_NAME" 2>/dev/null || echo "")

if [[ -n "$MEMORIES" ]]; then
  MSG="[OpenViking memory context]
${MEMORIES}
Use MCP tools (search, overview, read) if you need deeper historical context."
  json_msg=$(_json_encode_str "$MSG")
  echo "{\"hookSpecificOutput\": {\"hookEventName\": \"SubagentStart\", \"additionalContext\": $json_msg}}"
else
  echo '{}'
fi
