#!/usr/bin/env python3
"""WSGI application for Open Skies — the production entry point.

Serves the same routes as the stdlib dev server (server.py) through any WSGI
container. In production run it with waitress via serve.py; Python's docs
advise against exposing http.server publicly, waitress is built for it.
"""
import json
import mimetypes
import os
from urllib.parse import parse_qs

import server


def _resp(start_response, status, body, ctype, extra=()):
    headers = [("Content-Type", ctype), ("Content-Length", str(len(body)))]
    headers.extend(extra)
    start_response(status, headers)
    return [body]


def _json(start_response, obj, status="200 OK"):
    return _resp(
        start_response, status, json.dumps(obj).encode(), "application/json",
        [("Access-Control-Allow-Origin", "*"), ("Cache-Control", "no-store")],
    )


def app(environ, start_response):
    path = environ.get("PATH_INFO", "/") or "/"
    method = environ.get("REQUEST_METHOD", "GET")

    if method == "GET" and path == "/config.js":
        return _resp(start_response, "200 OK", server.config_body().encode(),
                     "text/javascript", [("Cache-Control", "no-store")])

    if method == "GET" and path == "/api/flight":
        qs = parse_qs(environ.get("QUERY_STRING", ""))
        fid = (qs.get("id") or [""])[0]
        entry = server.flight_entry(fid)
        return _json(start_response, entry or {"error": "not found"},
                     "200 OK" if entry else "404 Not Found")

    if method == "GET" and path == "/api/scores":
        return _json(start_response, server.top_scores())

    if method == "POST" and path == "/api/scores":
        try:
            n = int(environ.get("CONTENT_LENGTH") or 0)
            if n <= 0 or n > 256000:
                return _json(start_response, {"error": "invalid payload size"}, "413 Payload Too Large")
            data = json.loads(environ["wsgi.input"].read(n))
        except Exception:
            return _json(start_response, {"error": "bad json"}, "400 Bad Request")
        result = server.submit_score(data)
        if result is None:
            return _json(start_response, {"error": "bad json"}, "400 Bad Request")
        return _json(start_response, result, "201 Created")

    if method in ("GET", "HEAD") and server.static_allowed(path):
        rel = "index.html" if path == "/" else path.lstrip("/")
        full = os.path.realpath(os.path.join(server.BASE, rel))
        # Containment double-check on top of the allowlist.
        if full == os.path.realpath(server.BASE) or full.startswith(os.path.realpath(server.BASE) + os.sep):
            if os.path.isfile(full):
                ctype = mimetypes.guess_type(full)[0] or "application/octet-stream"
                with open(full, "rb") as f:
                    body = f.read()
                if method == "HEAD":
                    body = b""
                return _resp(start_response, "200 OK", body, ctype, [("Cache-Control", "no-cache")])

    return _json(start_response, {"error": "not found"}, "404 Not Found")
