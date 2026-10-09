#!/usr/bin/env python3
"""Local stand-in for Gatita's /v1/chat/completions, used only by run_tests.sh.

Streaming only. Tools are text protocol, not the API's tools field:
- If no system message explains <gatita-tool> blocks, it answers as plain chat.
- Turn 1: reasoning, then a <gatita-tool> block for list_files, split across chunks.
- Turn 2 (after a <gatita-tool-result> block): text, split across chunks, if the result shows App/GatitaApp.swift.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

EXPECTED_AUTH = "Bearer test-key"


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _sse(self, chunks):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        for chunk in chunks:
            self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
            self.wfile.flush()
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
        system_text = " ".join((m.get("content") or "") for m in messages if m.get("role") == "system")
        if "SKILL-TEST" in system_text:
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: skill seen"}}]}])
        if "<gatita-tool>" not in system_text:
            return self._sse([{"choices": [{"index": 0, "delta": {"content": "mock: no tool instructions"}}]}])

        results = [m for m in messages if m.get("role") == "user" and "<gatita-tool-result" in (m.get("content") or "")]
        user_texts = [m.get("content") or "" for m in messages if m.get("role") == "user"]
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
