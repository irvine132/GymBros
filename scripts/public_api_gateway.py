"""Narrow loopback gateway for the non-production Gym Bro Funnel route.

The Funnel handler targets /gym-bro; the incoming path is checked again here. No
client-controlled forwarding headers, redirects, cookies or arbitrary routes.
"""
import http.client
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

PREFIX = '/gym-bro/api/v1'
UUID = r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'
ROUTES = {
    'GET': (r'/me', r'/feed', r'/sessions', rf'/sessions/{UUID}', rf'/posts/{UUID}'),
    'POST': (r'/auth/register', r'/auth/login', r'/auth/logout', r'/sessions',
             rf'/sessions/{UUID}/complete', rf'/sessions/{UUID}/posts',
             rf'/posts/{UUID}/reports', rf'/users/{UUID}/block'),
    'PUT': (rf'/sessions/{UUID}',),
}
_lock = threading.Lock()
_windows = {'auth': [], 'write': []}


def route(method, target):
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or parsed.fragment or not parsed.path.startswith(PREFIX + '/'):
        return None
    suffix = parsed.path[len(PREFIX):]
    if not any(re.fullmatch(pattern, suffix) for pattern in ROUTES.get(method, ())):
        return None
    if parsed.query and not (method == 'GET' and suffix == '/feed' and
                             re.fullmatch(r'offset=(0|[1-9][0-9]{0,3})', parsed.query)):
        return None
    return '/api/v1' + suffix + (('?' + parsed.query) if parsed.query else '')


def admitted(method, path):
    group = 'auth' if path.startswith('/api/v1/auth/') else 'write'
    if method == 'GET' or (group == 'auth' and path == '/api/v1/auth/logout'):
        return True
    limit = 30 if group == 'auth' else 120
    now = time.monotonic()
    with _lock:
        _windows[group] = [t for t in _windows[group] if now - t < 60]
        if len(_windows[group]) >= limit:
            return False
        _windows[group].append(now)
    return True


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # No URL, credentials, body, Authorization or client address in logs.
        pass

    def do_GET(self): self.forward('GET')
    def do_POST(self): self.forward('POST')
    def do_PUT(self): self.forward('PUT')

    def forward(self, method):
        target = route(method, self.path)
        if target is None:
            self.send_error(404)
            return
        try:
            length = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            self.send_error(400)
            return
        if length < 0 or length > 65536 or self.headers.get('Transfer-Encoding'):
            self.send_error(413)
            return
        if not admitted(method, target):
            self.send_response(429)
            self.send_header('Retry-After', '60')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        body = self.rfile.read(length) if length else None
        conn = http.client.HTTPConnection('127.0.0.1', 18081, timeout=10)
        try:
            headers = {'Content-Type': 'application/json', 'Accept': 'application/json'}
            auth = self.headers.get('Authorization')
            if auth and re.fullmatch(r'Bearer [A-Za-z0-9._~+/-]{1,4096}', auth):
                headers['Authorization'] = auth
            conn.request(method, target, body=body, headers=headers)
            reply = conn.getresponse()
            data = reply.read(1048577)
            if len(data) > 1048576:
                self.send_error(502)
                return
            self.send_response(reply.status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(data)
        except (OSError, TimeoutError, http.client.HTTPException):
            self.send_error(502)
        finally:
            conn.close()


def main():
    server = ThreadingHTTPServer(('127.0.0.1', 18083), Handler)
    server.serve_forever()


if __name__ == '__main__':
    main()
