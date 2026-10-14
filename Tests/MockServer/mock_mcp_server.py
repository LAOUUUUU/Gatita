#!/usr/bin/env python3
"""A tiny MCP server over stdio for Gatita's tests: newline-delimited JSON-RPC with the tools echo, broken, and hang.
MOCK_MCP_MODE=silent never answers, and MOCK_MCP_MODE=slow waits a second before it answers initialize."""
import json
import os
import sys
import time

MODE = os.environ.get("MOCK_MCP_MODE", "")

TOOLS = [
    {"name": "echo", "description": "Echoes text back.\nUsed by the tests.",
     "inputSchema": {"type": "object", "properties": {"text": {"type": "string", "description": "What to echo"}},
                     "required": ["text"]}},
    {"name": "broken", "description": "Always fails.", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "hang", "description": "Never answers.", "inputSchema": {"type": "object", "properties": {}}},
]


def reply(message_id, result=None, error=None):
    body = {"jsonrpc": "2.0", "id": message_id}
    if error is not None:
        body["error"] = error
    else:
        body["result"] = result
    sys.stdout.write(json.dumps(body) + "\n")
    sys.stdout.flush()


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    message = json.loads(line)
    method = message.get("method")
    message_id = message.get("id")
    if message_id is None or MODE == "silent":
        continue  # a notification, such as notifications/initialized, or a server that never answers
    params = message.get("params") or {}
    if method == "initialize":
        if MODE == "slow":
            time.sleep(1)
        reply(message_id, {"protocolVersion": params.get("protocolVersion", "2025-11-25"),
                           "capabilities": {"tools": {"listChanged": False}},
                           "serverInfo": {"name": "mock", "version": "1.0"}})
    elif method == "tools/list":
        reply(message_id, {"tools": TOOLS})
    elif method == "tools/call":
        name = params.get("name")
        arguments = params.get("arguments") or {}
        if name == "hang":
            continue
        if name == "echo":
            reply(message_id, {"content": [{"type": "text", "text": "echo: " + str(arguments.get("text"))}], "isError": False})
        else:
            reply(message_id, {"content": [{"type": "text", "text": "it broke"}], "isError": True})
    elif method == "ping":
        reply(message_id, {})
    else:
        reply(message_id, error={"code": -32601, "message": "Method not found"})
