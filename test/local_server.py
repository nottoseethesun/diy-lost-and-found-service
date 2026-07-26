"""Local stand-in for the Apache routing, used by test/run.sh.

Mimics found-cgi/htaccess-docroot: GET /found/<20 alnum> is handed to
found.cgi (via PATH_INFO); every other path returns 404, exactly as Apache
would from the filesystem. Lets found-cgi/smoke-test.sh run end-to-end with no
web server installed.

Env (set by test/run.sh from test/test-config.json): TESTPORT, CGIDIR.
"""
import http.server
import os
import re
import socketserver
import subprocess  # nosec B404
import sys

PORT = int(os.environ["TESTPORT"])
CGI = os.environ["CGIDIR"]
SLUG = re.compile(r"^/found/([A-Za-z0-9]{20})$")
base_env = dict(
    os.environ,
    FOUND_CONFIG=os.path.join(CGI, "config.json"),
    FOUND_SLUGS=os.path.join(CGI, "slugs.txt"),
    FOUND_TEMPLATE=os.path.join(CGI, "page.html"),
)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if not SLUG.match(self.path):
            self.send_response(404)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"<!doctype html><title>Not Found</title>")
            return
        env = dict(base_env, PATH_INFO=self.path)
        # Fixed argv (interpreter + found.cgi), no shell, no untrusted input in
        # the command -- only the request path flows in as PATH_INFO, which
        # found.cgi re-validates against SLUG_PATTERN before any file access.
        out = subprocess.run(  # nosec B603
            [sys.executable, "found.cgi"], cwd=CGI, env=env, capture_output=True
        ).stdout
        head, _, body = out.partition(b"\r\n\r\n")
        status, ctype = 200, "text/html; charset=utf-8"
        for line in head.split(b"\r\n"):
            low = line.lower()
            if low.startswith(b"status:"):
                # best-effort parse of the CGI Status line; default to 200
                try:
                    status = int(line.split()[1])
                except Exception:  # nosec B110
                    pass
            elif low.startswith(b"content-type:"):
                ctype = line.split(b":", 1)[1].strip().decode() or ctype
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as srv:
    srv.serve_forever()
