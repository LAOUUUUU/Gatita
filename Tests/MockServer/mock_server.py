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
