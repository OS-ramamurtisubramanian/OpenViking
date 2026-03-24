"""OpenViking MCP Server (stdio transport).

Thin proxy to OpenViking HTTP server at localhost:1933.
Provides progressive L0→L1→L2 context loading tools.

Usage:
  claude mcp add openviking -- ~/.openviking/venv/bin/python ~/.openviking/mcp_server.py
"""

import json
import os
from urllib import request, error
from mcp.server.fastmcp import FastMCP

SERVER_URL = os.environ.get("OV_SERVER_URL", "http://127.0.0.1:1933")

mcp = FastMCP(
    name="openviking",
    instructions="OpenViking memory tools for progressive context loading. Use search() first (L0 abstracts), then overview() for more detail (L1), then read() for full content (L2). Only go deeper when needed.",
)


def _api(endpoint: str, payload: dict) -> dict:
    """Call OpenViking HTTP API."""
    req = request.Request(
        f"{SERVER_URL}{endpoint}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def _api_get(endpoint: str) -> dict:
    with request.urlopen(f"{SERVER_URL}{endpoint}", timeout=10) as resp:
        return json.loads(resp.read())


@mcp.tool()
def search(query: str, limit: int = 10) -> str:
    """Search OpenViking memory for relevant context. Returns L0 abstracts ranked by relevance.

    Use this first to find what memories exist. Then use overview() or read() to go deeper.

    Args:
        query: Natural language search query.
        limit: Max results to return (default 10).
    """
    data = _api("/api/v1/search/find", {"query": query, "limit": limit, "score_threshold": 0.25})
    results = data.get("result", {})

    lines = []
    for section in ["memories", "resources", "skills"]:
        for item in results.get(section, []):
            score = item.get("score", 0)
            uri = item.get("uri", "")
            abstract = item.get("abstract", "").strip()
            level = item.get("level", "?")
            lines.append(f"[L{level} {score:.3f}] {uri}\n  {abstract[:300]}")

    if not lines:
        return "No results found."
    return f"Found {len(lines)} results:\n\n" + "\n\n".join(lines)


@mcp.tool()
def overview(uri: str) -> str:
    """Load L1 overview of a resource or memory directory. More detail than L0 abstract but cheaper than full L2 content.

    Usually sufficient for understanding scope and making decisions.

    Args:
        uri: Viking URI (e.g. viking://user/default/memories/preferences).
    """
    from urllib.parse import quote
    data = _api_get(f"/api/v1/content/overview?uri={quote(uri, safe='')}")
    content = data.get("result", "")
    if not content:
        return f"No overview available for {uri}"
    return content


@mcp.tool()
def read(uri: str) -> str:
    """Load full L2 content of a specific resource. Only use when L1 overview isn't enough.

    Args:
        uri: Viking URI (e.g. viking://user/default/memories/preferences/mem_abc.md).
    """
    from urllib.parse import quote
    data = _api_get(f"/api/v1/content/read?uri={quote(uri, safe='')}")
    content = data.get("result", "")
    if not content:
        return f"No content at {uri}"
    return content


if __name__ == "__main__":
    mcp.run(transport="stdio")
