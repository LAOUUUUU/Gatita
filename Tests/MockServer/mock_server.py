#!/usr/bin/env python3
"""Local stand-in for Gatita's /v1/chat/completions, used only by run_tests.sh.

Streaming only. Tools are text protocol, not the API's tools field. A marker word in a user message picks a
scenario in which a reply would otherwise just end: EMPTY-AFTER-TOOL, CUT-OFF, NO-CLOSE-TAG, BROKEN-BLOCK,
COLON-END, DROPPED, ALWAYS-EMPTY, RATE-LIMIT-ONCE (a 429, then an answer), and RATE-LIMIT-ALWAYS. The default flow:
- If no system message explains <gatita-tool> blocks, it answers as plain chat.
- Turn 1: reasoning, then a <gatita-tool> block for list_files, split across chunks.
- Turn 2 (after a <gatita-tool-result> block): text, split across chunks, if the result shows App/GatitaApp.swift.
"""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

EXPECTED_AUTH = "Bearer test-key"
# How many requests have asked for the RATE-LIMIT-ONCE scenario. Odd ones get a 429.
RATE_LIMITED = {"count": 0}


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, payload, headers=None):
        data = json.dumps(payload).encode()
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _sse(self, chunks, done=True):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        for chunk in chunks:
            self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
            self.wfile.flush()
        if done:
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            return self._json(404, {"error": "not found"})
        if self.headers.get("Authorization") != EXPECTED_AUTH:
            return self._json(401, {"error": "bad auth"})
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if not body.get("stream"):
            return self._json(400, {"error": "stream required"})

        messages = body.get("messages", [])
        everything = " ".join((m.get("content") or "") for m in messages if isinstance(m.get("content"), str))
        limited = {"error": "Rate limit exceeded", "message": "Rate limit: 10 requests per minute", "retryAfter": 1}
        if "RATE-LIMIT-ALWAYS" in everything:
            return self._json(429, limited, {"Retry-After": "1"})
        if "RATE-LIMIT-ONCE" in everything:
            RATE_LIMITED["count"] += 1
            if RATE_LIMITED["count"] % 2 == 1:
                return self._json(429, limited, {"Retry-After": "1"})
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: answered after the rate limit"}}]},
                              {"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}])
        system_text = " ".join((m.get("content") or "") for m in messages if m.get("role") == "system")
        if "SKILL-TEST" in system_text:
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: skill seen"}}]}])
        if "<gatita-tool>" not in system_text:
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: no tool instructions"}}]}])

        results = [m for m in messages if m.get("role") == "user" and "<gatita-tool-result" in (m.get("content") or "")]
        user_texts = [m.get("content") or "" for m in messages if m.get("role") == "user"]
        last_text = (messages[-1].get("content") or "") if messages else ""
        stop = {"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}
        empty_turn = [{"choices": [{"index": 0, "delta": {"role": "assistant", "reasoning_content": "thinking only"}}]}, stop]
        first_turn = [
            {"choices": [{"index": 0, "delta": {"content": "Let me look. <gatita-tool>{\"tool\": \"list_files\", \"path\": \".\"}</gatita-tool>"}}]},
            stop,
        ]
        marker = next((name for name in ("EMPTY-AFTER-TOOL", "CUT-OFF", "NO-CLOSE-TAG", "BROKEN-BLOCK", "COLON-END", "DROPPED", "ALWAYS-EMPTY")
                       if any(name in text for text in user_texts)), None)
        if marker == "ALWAYS-EMPTY":
            return self._sse(empty_turn)
        if marker == "DROPPED":
            # The connection closes with no finish_reason and no [DONE].
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: partial reply"}}]}], done=False)
        if marker == "CUT-OFF":
            if "Continue exactly where you stopped" in last_text:
                return self._sse([{"choices": [{"index": 0, "delta": {"content": "second half."}}]}, stop])
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: first half, "}}]},
                              {"choices": [{"index": 0, "delta": {}, "finish_reason": "length"}]}])
        if marker == "COLON-END":
            if "ended with a colon" in last_text:
                return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: done after the nudge."}}]}, stop])
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "Checking the task:"}}]}, stop])
        if marker == "EMPTY-AFTER-TOOL" and results:
            if "Your last message was empty" in last_text:
                return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: recovered after an empty reply"}}]}, stop])
            return self._sse(empty_turn)
        if marker == "NO-CLOSE-TAG" and not results:
            return self._sse([
                {"choices": [{"index": 0, "delta": {"content": "Let me look. <gatita-tool>{\"tool\": \"list_files\", \"path\": \".\"}"}}]},
                stop,
            ])
        if marker == "BROKEN-BLOCK" and not results:
            if "cut off before it finished" in last_text:
                return self._sse(first_turn)
            return self._sse([
                {"choices": [{"index": 0, "delta": {"content": "Let me look. <gatita-tool>{\"tool\": \"list_fi"}}]},
                stop,
            ])
        if any("BATCH-TEST" in text for text in user_texts):
            if results:
                text = results[-1]["content"]
                ok = "===== result 2: read_file =====" in text and "let app = 1" in text and "App/GatitaApp.swift" in text
                return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: batch ok" if ok else "mock: batch result missing"}}]}, stop])
            batch = {"tool": "batch", "calls": [{"tool": "list_files", "path": "."}, {"tool": "read_file", "path": "App/GatitaApp.swift"}]}
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "<gatita-tool>" + json.dumps(batch) + "</gatita-tool>"}}]}, stop])
        if any("MCP-CHECK" in text for text in user_texts):
            if results:
                inner = re.sub(r"</?gatita-tool-result[^>]*>", "", results[-1]["content"]).strip()
                return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: " + inner}}]}, stop])
            call = {"tool": "mcp__mock__echo", "text": "hi"}
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "<gatita-tool>" + json.dumps(call) + "</gatita-tool>"}}]}, stop])
        if any("WRITE-CHECK" in text for text in user_texts):
            if results:
                return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: wrote"}}]}, stop])
            batch = {"tool": "batch", "calls": [
                {"tool": "edit_file", "path": "App/GatitaApp.swift", "old_text": "let app = 1", "new_text": "let app = 2"},
                {"tool": "write_file", "path": "App/New.swift", "content": "let new = 1\n"}]}
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "<gatita-tool>" + json.dumps(batch) + "</gatita-tool>"}}]}, stop])
        if any("RUN-CHECK" in text for text in user_texts):
            if results:
                denied = "denied" in results[-1]["content"]
                return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: denied" if denied else "mock: ran"}}]}, stop])
            run = {"tool": "run_command", "command": "swift --version"}
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "<gatita-tool>" + json.dumps(run) + "</gatita-tool>"}}]}, stop])
        if not results and any("ASK-ME" in text for text in user_texts):
            return self._sse([
                {"choices": [{"index": 0, "delta": {"content": "<gatita-tool>{\"tool\": \"ask_user\", \"question\": \"Which file should I read?\"}</gatita-tool>"}}]},
                {"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]},
            ])
        if not results:
            return self._sse([
                {"choices": [{"index": 0, "delta": {"role": "assistant", "reasoning_content": "Looking at "}}]},
                {"choices": [{"index": 0, "delta": {"reasoning_content": "the project."}}]},
                {"choices": [{"index": 0, "delta": {"content": "Let me look. <gatita-tool>{\"tool\": \"list_files\", "}}]},
                {"choices": [{"index": 0, "delta": {"content": "\"path\": \".\"}</gatita-tool>"}}]},
                {"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]},
            ])

        result_text = results[-1]["content"]
        if "App/GatitaApp.swift" in result_text:
            pieces = ["mock: found ", "App/GatitaApp.swift"]
        else:
            pieces = ["mock: tool output missing"]
        return self._sse([{"choices": [{"index": 0, "delta": {"content": piece}}]} for piece in pieces]
                         + [{"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}])

    def log_message(self, fmt, *args):
        sys.stderr.write("[mock] " + (fmt % args) + "\n")


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
