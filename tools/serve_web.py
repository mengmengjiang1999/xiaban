#!/usr/bin/env python3
"""Serve a Godot Web build locally for browser testing."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class DevelopmentHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
    }

    def send_head(self):
        # SimpleHTTPRequestHandler otherwise follows links outside its root.
        root = Path(self.directory).resolve()
        requested = Path(self.translate_path(self.path)).resolve()
        try:
            requested.relative_to(root)
            if requested.is_dir():
                for name in ("index.html", "index.htm"):
                    index = requested / name
                    if index.exists():
                        index.resolve().relative_to(root)
                        break
        except ValueError:
            self.send_error(404, "Not found")
            return None
        return super().send_head()

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


def main():
    default_directory = Path(__file__).resolve().parent.parent / "builds" / "web"
    parser = argparse.ArgumentParser(
        description="Preview a Godot Web export on 127.0.0.1 only."
    )
    parser.add_argument("--port", type=int, default=8765, help="local port (default: 8765)")
    parser.add_argument(
        "--directory",
        type=Path,
        default=default_directory,
        help="export directory (default: ../builds/web relative to this script)",
    )
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    directory = args.directory.expanduser().resolve()
    if not directory.is_dir():
        parser.error(f"export directory does not exist: {directory}")

    handler = partial(DevelopmentHandler, directory=str(directory))
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    except OSError as error:
        parser.error(f"cannot start local server: {error}")
    with server:
        print(f"Serving {directory}", flush=True)
        print(f"Open http://127.0.0.1:{args.port}/ — Ctrl+C to stop.", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
