#!/usr/bin/env python3
# Production server for Railway (or any host): serves the app + leaderboard API.
# - Listens on $PORT (Railway sets it).
# - Injects the Google Maps key from $GOOGLE_MAPS_API_KEY into /config.js, so the
#   key lives in env vars, not in the repo.
# - Stores scores in $DATA_DIR (attach a Railway volume there to persist them).
import json, os, threading, uuid
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

BASE = os.path.dirname(os.path.abspath(__file__))
DATA = os.environ.get("DATA_DIR", BASE)
SCORES = os.path.join(DATA, "scores.json")
PORT = int(os.environ.get("PORT", "8000"))
API_KEY = os.environ.get("GOOGLE_MAPS_API_KEY", "")
LOCK = threading.Lock()


def load():
    try:
        with open(SCORES) as f:
            return json.load(f)
    except Exception:
        return []


def save(scores):
    tmp = SCORES + ".tmp"
    with open(tmp, "w") as f:
        json.dump(scores, f)
    os.replace(tmp, SCORES)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=BASE, **k)

    def log_message(self, *a):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _text(self, body, ctype="text/javascript"):
        b = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/config.js" or self.path.startswith("/config.js?"):
            return self._text('window.HORSEBACK_CONFIG = { GOOGLE_MAPS_API_KEY: %s };' % json.dumps(API_KEY))
        if self.path.startswith("/api/flight"):
            fid = ""
            if "?" in self.path:
                for kv in self.path.split("?", 1)[1].split("&"):
                    if kv.startswith("id="):
                        fid = kv[3:]
            with LOCK:
                entry = next((e for e in load() if e.get("id") == fid), None)
            return self._json(entry or {"error": "not found"}, 200 if entry else 404)
        if self.path.startswith("/api/scores"):
            with LOCK:
                top = sorted(load(), key=lambda x: -x.get("distanceKm", 0))[:20]
            return self._json([{k: v for k, v in e.items() if k != "path"} for e in top])
        return super().do_GET()

    def do_POST(self):
        if self.path.startswith("/api/scores"):
            try:
                n = int(self.headers.get("Content-Length", 0))
                data = json.loads(self.rfile.read(n) or b"{}")
            except Exception:
                return self._json({"error": "bad json"}, 400)
            name = "".join(c for c in str(data.get("name", "")) if c.isalnum() or c in " -_")[:10] or "PILOT"
            path = data.get("path") or []
            if not isinstance(path, list):
                path = []
            entry = {
                "id": uuid.uuid4().hex[:8],
                "name": name.upper(),
                "distanceKm": round(float(data.get("distanceKm", 0) or 0), 2),
                "timeSec": int(float(data.get("timeSec", 0) or 0)),
                "topSpeedKmh": int(float(data.get("topSpeedKmh", 0) or 0)),
                "path": path[:800],
            }
            with LOCK:
                scores = load()
                scores.append(entry)
                scores = sorted(scores, key=lambda x: -x.get("distanceKm", 0))[:300]
                save(scores)
                top = scores[:20]
            return self._json({"id": entry["id"], "board": [{k: v for k, v in e.items() if k != "path"} for e in top]}, 201)
        self.send_response(404)
        self.end_headers()


if __name__ == "__main__":
    print("Open Skies on :%d (data: %s, key set: %s)" % (PORT, DATA, bool(API_KEY)))
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
