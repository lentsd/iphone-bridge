#!/usr/bin/env python3
"""Temporary loopback Go module proxy using macOS curl for HTTPS.

Only proxy.golang.org is fetched. Go still validates go.sum and the checksum
database. Nothing changes in system proxy settings or the user's Go config.
"""
import hashlib
import http.server
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / ".build" / "go-curl-cache"
CACHE.mkdir(parents=True, exist_ok=True)
LIMIT = threading.Semaphore(4)


class Proxy(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.scheme or parsed.netloc or ".." in parsed.path.split("/"):
            self.send_error(400)
            return
        key = hashlib.sha256(self.path.encode()).hexdigest()
        cached = CACHE / key
        code = 200
        if not cached.exists():
            with LIMIT:
                descriptor, temporary = tempfile.mkstemp(dir=CACHE)
                os.close(descriptor)
                try:
                    result = subprocess.run([
                        "/usr/bin/curl", "--http1.1", "--silent", "--show-error", "--location",
                        "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "10",
                        "--max-time", "90", "--max-filesize", "268435456", "--retry", "2",
                        "--retry-all-errors", "--output", temporary, "--write-out", "%{http_code}",
                        "https://proxy.golang.org" + self.path,
                    ], capture_output=True, text=True)
                    if result.returncode:
                        print("Module download failed: " + parsed.path + " · " + str(result.returncode) + " · " + result.stderr[-250:], file=sys.stderr, flush=True)
                        self.send_error(502)
                        return
                    code = int(result.stdout)
                    if code == 200:
                        os.replace(temporary, cached)
                    else:
                        body = pathlib.Path(temporary).read_bytes()
                        self.send_response(code)
                        self.send_header("Content-Length", str(len(body)))
                        self.end_headers()
                        self.wfile.write(body)
                        return
                finally:
                    pathlib.Path(temporary).unlink(missing_ok=True)
        self.send_response(code)
        self.send_header("Content-Length", str(cached.stat().st_size))
        self.end_headers()
        with cached.open("rb") as stream:
            try:
                shutil.copyfileobj(stream, self.wfile, length=512 * 1024)
            except (BrokenPipeError, ConnectionResetError):
                pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
environment = dict(os.environ)
environment["GOPROXY"] = f"http://127.0.0.1:{server.server_port}"
environment["GOCACHE"] = str(ROOT / ".build" / "go-cache")
environment["GOPATH"] = str(ROOT / ".build" / "go-path")
environment["GOMODCACHE"] = str(ROOT / ".build" / "go-mod-cache")
try:
    result = subprocess.run(sys.argv[1:], env=environment)
finally:
    server.shutdown()
sys.exit(result.returncode)
