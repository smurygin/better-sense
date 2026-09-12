#!/usr/bin/env python3
"""Run compiled production AS3 code with test doubles in Ruffle/Chromium.

This deliberately executes only project test SWFs, never the game's
SWC libraries or the production UI. Native Scaleform behavior requires the game.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

from bootstrap import CACHE, ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chromium", default=shutil.which("chromium") or shutil.which("google-chrome"))
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--swf", type=Path, default=ROOT / "build/DecimalInputTests.swf")
    parser.add_argument("--no-sandbox", action="store_true", help="for container environments where Chromium cannot create its sandbox")
    args = parser.parse_args()
    if not args.chromium:
        parser.error("Chromium is required (or provide --chromium)")
    swf = args.swf.resolve()
    if swf.parent != ROOT / "build" or swf.name not in ("DecimalInputTests.swf", "SensitivityInputTests.swf"):
        parser.error("Only compiled project test SWFs in build/ may run in this harness")
    runtime = CACHE / "toolchain/package"
    if not swf.is_file() or not (runtime / "ruffle.js").is_file():
        parser.error("Run tools/bootstrap.py --test-runtime and tools/build.py --as3-tests first")
    finished = threading.Event()
    result = {}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            if self.path == "/":
                source = ROOT / "tools/ruffle-tests.html"
            elif self.path == "/DecimalInputTests.swf":
                source = swf
            elif self.path.startswith("/runtime/") and "/" not in self.path[len("/runtime/"):] and ".." not in self.path:
                source = runtime / self.path[len("/runtime/"):]
            else:
                self.send_error(404)
                return
            if not source.is_file():
                self.send_error(404)
                return
            content = source.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", mimetypes.guess_type(source)[0] or "application/octet-stream")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)

        def do_POST(self):
            if self.path != "/result":
                self.send_error(404)
                return
            payload = self.rfile.read(min(int(self.headers.get("Content-Length", "0")), 65536))
            result.update(json.loads(payload))
            self.send_response(204)
            self.end_headers()
            finished.set()

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    with tempfile.TemporaryDirectory(prefix="better-sense-chromium-") as profile:
        command = [args.chromium, "--headless", "--disable-gpu", "--no-first-run", "--no-default-browser-check", "--disable-background-networking", "--user-data-dir=" + profile]
        if args.no_sandbox:
            command.append("--no-sandbox")
        command.append("http://127.0.0.1:" + str(server.server_port) + "/")
        log = ROOT / "build/as3-runtime.log"
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            try:
                if not finished.wait(args.timeout):
                    raise SystemExit("AS3 runtime timed out; see " + str(log))
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                server.shutdown()
                server.server_close()
    print(result.get("message", "No AS3 test result"))
    if result.get("success") is not True:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
