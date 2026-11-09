# test server: always responds with brotli-compressed body; logs client Accept-Encoding
import http.server, sys
BODY = open(sys.argv[1], 'rb').read()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(__import__('os').path.join(__import__('os').path.dirname(__import__('os').path.abspath(__file__)), 'ae.log'), 'a') as f: f.write(self.headers.get('Accept-Encoding', '-') + '\n')
        self.send_response(200); self.send_header('Content-Encoding', 'br')
        self.send_header('Content-Length', str(len(BODY))); self.end_headers(); self.wfile.write(BODY)
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', 8765), H).serve_forever()
