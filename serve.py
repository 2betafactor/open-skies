#!/usr/bin/env python3
"""Production launcher: waitress serving the WSGI app, with a stdlib fallback
so local development still works with zero dependencies."""
import os

PORT = int(os.environ.get("PORT", "8000"))

try:
    from waitress import serve

    from wsgi import app

    print("Open Skies (waitress) on :%d" % PORT, flush=True)
    serve(app, host="0.0.0.0", port=PORT, threads=8)
except ImportError:
    import server

    print("waitress not installed — falling back to the stdlib dev server", flush=True)
    server.ThreadingHTTPServer(("0.0.0.0", PORT), server.Handler).serve_forever()
