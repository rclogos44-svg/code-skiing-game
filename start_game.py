#!/usr/bin/env python3
"""Serve only the extracted game directory on loopback, then open the browser."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import threading
import webbrowser

root = Path(__file__).resolve().parent
if not (root / 'index.html').is_file() or not (root / 'data').is_dir():
    sys.exit('Extract the entire SUMMIT ZIP before starting the game.')
handler = partial(SimpleHTTPRequestHandler, directory=str(root))
with ThreadingHTTPServer(('127.0.0.1', 0), handler) as server:
    address = f'http://127.0.0.1:{server.server_port}/'
    print(f'SUMMIT is running at {address}', flush=True)
    print('Keep this window open while playing. Press Ctrl+C to stop.', flush=True)
    if '--no-browser' not in sys.argv:
        threading.Timer(0.5, lambda: webbrowser.open(address)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
