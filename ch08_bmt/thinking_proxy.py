"""Loopback-only evaluation adapter: explicitly set Ollama reasoning effort.

Only chat requests for the evaluation alias are accepted. The downstream SSE
bytes are forwarded unchanged and recorded to verify actual thinking activity.
No production configuration is modified.
"""
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading
import uuid


class ThinkingProxy:
    def __init__(self, output, alias, think=True, port=11434):
        self.output = Path(output)
        self.output.mkdir(parents=True, exist_ok=False)
        self.alias = alias
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                if self.path != '/v1/chat/completions':
                    self.send_error(404)
                    return
                raw = self.rfile.read(int(self.headers.get('Content-Length', '0')))
                payload = json.loads(raw)
                if payload.get('model') != owner.alias:
                    self.send_error(403)
                    return
                key = uuid.uuid4().hex
                (owner.output / (key + '-incoming.json')).write_bytes(raw)
                payload['reasoning_effort'] = 'high' if think else 'none'
                body = json.dumps(payload, ensure_ascii=False).encode('utf-8')
                (owner.output / (key + '-forwarded.json')).write_bytes(body)
                conn = http.client.HTTPConnection('127.0.0.1', port, timeout=180)
                try:
                    conn.request('POST', self.path, body, {'Content-Type': 'application/json'})
                    response = conn.getresponse()
                    self.send_response(response.status)
                    self.send_header('Content-Type', response.getheader('Content-Type', 'application/json'))
                    self.send_header('Connection', 'close')
                    self.end_headers()
                    with (owner.output / (key + '-response.bin')).open('wb') as captured:
                        while True:
                            chunk = response.read1(65536)
                            if not chunk:
                                break
                            captured.write(chunk)
                            captured.flush()
                            self.wfile.write(chunk)
                            self.wfile.flush()
                except (OSError, http.client.HTTPException) as exc:
                    (owner.output / (key + '-error.txt')).write_text(str(exc))
                finally:
                    conn.close()

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def start(self):
        self.thread.start()
        return 'http://127.0.0.1:%s/v1' % self.server.server_port

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(5)
