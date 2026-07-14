#!/usr/bin/env python3

import http.server
import pathlib
import re
import subprocess
import sys
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, format, *args):
        pass


def duration_seconds(value, unit):
    scales = {"us": 1e-6, "ms": 1e-3, "s": 1.0}
    return float(value) * scales[unit]


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else root / "wrk")
    if not binary.is_absolute():
        binary = root / binary

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    serving = threading.Thread(target=server.serve_forever, daemon=True)
    serving.start()

    try:
        port = server.server_address[1]
        command = [
            str(binary),
            "-d1s",
            "-c12",
            "-t12",
            "-R120",
            "-s", str(root / "tests" / "delayed_setup.lua"),
            "http://127.0.0.1:{}/".format(port),
        ]
        result = subprocess.run(
            command,
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            timeout=10,
        )
    finally:
        server.shutdown()
        server.server_close()

    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        return result.returncode

    match = re.search(r"([0-9]+) requests in ([0-9.]+)(us|ms|s),", result.stdout)
    if not match:
        sys.stderr.write("unable to find reported runtime in output:\n")
        sys.stderr.write(result.stdout)
        return 1

    requests = int(match.group(1))
    runtime = duration_seconds(match.group(2), match.group(3))
    if requests == 0:
        sys.stderr.write("expected the test server to complete requests\n")
        sys.stderr.write(result.stdout)
        return 1

    if runtime < 0.75 or runtime > 2.5:
        sys.stderr.write(
            "expected a roughly 1 second measured run after worker setup; "
            "got {:.6f}s\n".format(runtime)
        )
        sys.stderr.write(result.stdout)
        return 1

    print("thread start timing: {:.2f}s reported after delayed setup".format(runtime))
    return 0


if __name__ == "__main__":
    sys.exit(main())
