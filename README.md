# ✈️ Open Skies

Fly a plane over **photorealistic 3D of the real world** — search any location (or
pick a preset) and take off over Google's Photorealistic 3D Tiles, rendered with
**CesiumJS**. Land to post your **distance flown** to a shared **leaderboard**, and
every flight is **recorded** so you can share a link that **replays** it.

Vanilla HTML/CSS/JS front end + a tiny Python standard-library server (static files
+ leaderboard API). No build step, no framework, no third-party Python packages.

## Features
- Free-flight arcade model over real 3D terrain, with a chase camera, HUD
  (airspeed / altitude / heading / throttle), engine + wind audio, and a
  golden-hour look.
- **Graphics toggle** — Performance / Balanced / Quality (photorealistic tiles are
  GPU-heavy; pick your trade-off).
- **Leaderboard** ranked by distance flown, with medals.
- **Flight recording + shareable replays** — `/?flight=<id>` replays a saved flight.

## Controls
`W/S` pitch · `A/D` roll · `Q/E` rudder · `Shift/Ctrl` throttle · `Esc` / **Land** to finish.

## Run locally
1. Get a Google Maps API key ([Cloud Console](https://console.cloud.google.com/))
   and enable: **Map Tiles API**, **Maps JavaScript API**, **Places API**.
2. `cp config.example.js config.js` and paste your key (config.js is gitignored).
3. Serve it:
   ```bash
   python3 server.py            # serves the app + leaderboard on :8000
   # (server.py reads the key from $GOOGLE_MAPS_API_KEY, or from config.js locally)
   ```
4. Open http://localhost:8000

## Deploy (Railway or any host)
`server.py` is production-ready: it listens on `$PORT` and injects the key from the
`GOOGLE_MAPS_API_KEY` env var into `/config.js`, so **the key never lives in the
repo**. Leaderboard scores are written to `$DATA_DIR` (mount a persistent volume
there so they survive redeploys).

Env vars:
- `GOOGLE_MAPS_API_KEY` — your Maps key (**restrict it by HTTP referrer** to your
  deployed domain).
- `DATA_DIR` *(optional)* — directory for `scores.json` (default: repo dir).
- `PORT` — set automatically by most hosts.

## Notes
- Google Map Tiles / Places calls are **metered** — set a billing budget and
  restrict the key by referrer before sharing publicly.
- Rendering photorealistic 3D of a whole city in real time is GPU-heavy; use
  **Performance** mode on weaker machines.

## Structure
```
index.html / style.css     UI + screens
server.py                  static server + leaderboard API (stdlib only)
src/flight.js              Cesium flight engine (physics, camera, replay, tiles)
src/main.js                app state machine, vehicle/graphics/leaderboard wiring
src/{controller,hud,audio,tuner}.js
assets/plane.glb           aircraft model (CC0)
```
