#!/usr/bin/env python3
# Production server for Railway (or any host): serves the app + leaderboard API.
# - Listens on $PORT (Railway sets it).
# - Injects the Google Maps key from $GOOGLE_MAPS_API_KEY into /config.js, so the
#   key lives in env vars, not in the repo.
# - Stores scores in $DATA_DIR (attach a Railway volume there to persist them).
import json, os, re, threading, uuid, math
from urllib.parse import urlsplit, urlencode, parse_qs
from urllib.request import urlopen
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
    os.makedirs(DATA, exist_ok=True)
    tmp = SCORES + ".tmp"
    with open(tmp, "w") as f:
        json.dump(scores, f)
    os.replace(tmp, SCORES)


# ---- App logic, shared by the stdlib dev server below and wsgi.py (the
# production entry point served by waitress — see serve.py). ----

def config_body():
    if not API_KEY:
        try:
            with open(os.path.join(BASE, "config.js")) as f:
                return f.read()
        except FileNotFoundError:
            pass
    return 'window.HORSEBACK_CONFIG = { GOOGLE_MAPS_API_KEY: %s };' % json.dumps(API_KEY)


def flight_entry(fid):
    with LOCK:
        return next((e for e in load() if e.get("id") == fid), None)


def top_scores():
    with LOCK:
        top = sorted(load(), key=lambda x: -x.get("distanceKm", 0))[:20]
    return [{k: v for k, v in e.items() if k != "path"} for e in top]


def submit_score(data):
    """Validate and store one score. Returns {'id','board'} or None if invalid."""
    try:
        if not isinstance(data, dict):
            raise ValueError("expected object")
        for key in ("distanceKm", "timeSec", "topSpeedKmh"):
            value = data.get(key, 0)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                raise ValueError("invalid statistic")
        path = data.get("path", [])
        if not isinstance(path, list) or len(path) > 800:
            raise ValueError("invalid path")
        for point in path:
            if not isinstance(point, list) or len(point) != 4 or any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in point):
                raise ValueError("invalid point")
            if not -180 <= point[0] <= 180 or not -90 <= point[1] <= 90:
                raise ValueError("invalid coordinates")
        if data.get("vehicle", "plane") not in ("plane", "spaceship", "cyberwing", "skylark", "swift"):
            raise ValueError("invalid vehicle")
        if data.get("world", "google") != "google":
            raise ValueError("invalid world")
    except Exception:
        return None
    name = "".join(c for c in str(data.get("name", "")) if c.isalnum() or c in " -_")[:10] or "PILOT"
    entry = {
        "id": uuid.uuid4().hex[:8],
        "name": name.upper(),
        "distanceKm": round(float(data.get("distanceKm", 0) or 0), 2),
        "timeSec": int(float(data.get("timeSec", 0) or 0)),
        "topSpeedKmh": int(float(data.get("topSpeedKmh", 0) or 0)),
        "path": path[:800],
        "world": data.get("world", "google"),
        "vehicle": data.get("vehicle", "plane"),
    }
    with LOCK:
        # Always retain the flight whose share link we return, even below the leaderboard.
        scores = sorted(load(), key=lambda x: -x.get("distanceKm", 0))[:299]
        scores.append(entry)
        save(scores)
        top = sorted(scores, key=lambda x: -x.get("distanceKm", 0))[:20]
    return {"id": entry["id"], "board": [{k: v for k, v in e.items() if k != "path"} for e in top]}


def api_key():
    """The Google Maps key: env var in production, config.js locally."""
    if API_KEY:
        return API_KEY
    try:
        with open(os.path.join(BASE, "config.js")) as f:
            m = re.search(r"AIza[A-Za-z0-9_\-]+", f.read())
            return m.group(0) if m else ""
    except FileNotFoundError:
        return ""


def search_places(query):
    """Geocode a free-text place via the Google Geocoding API.
    Returns [{name, lat, lon}] (at most 6). The key stays server side."""
    q = (query or "").strip()
    if not q or len(q) > 200:
        return []
    key = api_key()
    if not key:
        return []
    url = "https://maps.googleapis.com/maps/api/geocode/json?" + urlencode({"address": q, "key": key})
    try:
        with urlopen(url, timeout=8) as r:
            data = json.loads(r.read().decode())
    except Exception:
        return []
    out = []
    for res in data.get("results", [])[:6]:
        loc = res.get("geometry", {}).get("location", {})
        if "lat" in loc and "lng" in loc:
            out.append({"name": res.get("formatted_address", q), "lat": loc["lat"], "lon": loc["lng"]})
    return out


PLAY_DIR = os.path.join(BASE, "play")   # Godot web export (see godot/build.sh)


def play_available():
    return os.path.isfile(os.path.join(PLAY_DIR, "index.html"))


def read_static(full, accept_encoding=""):
    """Read a static file; prefer a pre-compressed `.gz` sibling (the Godot
    wasm is ~40 MB raw, ~10 MB gzipped) when the client accepts gzip. Only
    the .gz files are committed/deployed, so if the raw file is missing the
    gzip is served regardless (every browser understands it)."""
    gz = full + ".gz"
    if os.path.isfile(gz) and ("gzip" in (accept_encoding or "") or not os.path.isfile(full)):
        with open(gz, "rb") as f:
            return f.read(), "gzip"
    with open(full, "rb") as f:
        return f.read(), None


def static_exists(full):
    return os.path.isfile(full) or os.path.isfile(full + ".gz")


def static_allowed(path):
    """Serve only public game assets, never source data or repository files."""
    if ".." in path or "%" in path or (path.endswith("/") and path not in ("/", "/play/")):
        return False
    return path in ("/", "/index.html", "/style.css", "/favicon.ico", "/classic", "/play/") or path.startswith(("/src/", "/assets/", "/play/"))


def redirect_target(path):
    """The Godot build lives under /play/ (its asset URLs are relative), so
    the root redirects there when a build exists; the Cesium app is /classic."""
    if path == "/" and play_available():
        return "/play/"
    return None


def resolve_static(path):
    """Map a URL path to a file under BASE."""
    if path == "/" or path == "/classic":
        return os.path.join(BASE, "index.html")
    if path == "/play/":
        return os.path.join(PLAY_DIR, "index.html")
    return os.path.join(BASE, path.lstrip("/"))


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=BASE, **k)

    def end_headers(self):
        if urlsplit(self.path).path not in ("/config.js",) and not self.path.startswith("/api/"):
            self.send_header("Cache-Control", "no-cache")
        super().end_headers()

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
            return self._text(config_body())
        if urlsplit(self.path).path == "/api/flight":
            fid = ""
            if "?" in self.path:
                for kv in self.path.split("?", 1)[1].split("&"):
                    if kv.startswith("id="):
                        fid = kv[3:]
            entry = flight_entry(fid)
            return self._json(entry or {"error": "not found"}, 200 if entry else 404)
        if urlsplit(self.path).path == "/api/scores":
            return self._json(top_scores())
        if urlsplit(self.path).path == "/api/config":
            return self._json({"key": api_key()})
        if urlsplit(self.path).path == "/api/search":
            q = (parse_qs(urlsplit(self.path).query).get("q") or [""])[0]
            return self._json({"results": search_places(q)})
        path = urlsplit(self.path).path
        target = redirect_target(path)
        if target:
            self.send_response(302)
            self.send_header("Location", target)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if not static_allowed(path):
            return self._json({"error": "not found"}, 404)
        full = resolve_static(path)
        if not static_exists(full):
            return self._json({"error": "not found"}, 404)
        return self._send_file(full)

    def _send_file(self, full):
        ctype = self.guess_type(full)
        if full.endswith(".wasm"):
            ctype = "application/wasm"
        body, encoding = read_static(full, self.headers.get("Accept-Encoding", ""))
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if encoding:
            self.send_header("Content-Encoding", encoding)
            self.send_header("Vary", "Accept-Encoding")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if urlsplit(self.path).path == "/api/scores":
            try:
                n = int(self.headers.get("Content-Length", 0))
                if n <= 0 or n > 256000:
                    return self._json({"error": "invalid payload size"}, 413)
                data = json.loads(self.rfile.read(n))
            except Exception:
                return self._json({"error": "bad json"}, 400)
            result = submit_score(data)
            if result is None:
                return self._json({"error": "bad json"}, 400)
            return self._json(result, 201)
        self.send_response(404)
        self.end_headers()


if __name__ == "__main__":
    print("Open Skies on :%d (data: %s, key set: %s)" % (PORT, DATA, bool(API_KEY)))
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
