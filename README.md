# ✈️ Open Skies

Fly a plane over **photorealistic 3D of the real world** — search any location (or
pick a preset) and take off over Google's Photorealistic 3D Tiles, rendered with
**CesiumJS**. Finish a flight to post your **distance flown** to a shared **leaderboard**, and
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
`W/S` pitch · `A/D` roll · `Q/E` rudder · `Shift/Ctrl` throttle · `Esc` / **Finish** to finish.

## Run locally
Run `python3 server.py` and open http://localhost:8000. **Real world** is the
default, with the original location search, presets, and real-world flights.
Choose **Sandbox**, then **Fly in Sandbox**, for the optional practice environment:
a generated airfield, fields, trees, and an eight-gate
practice course. It makes no Google requests and requires no API key or paid map
service. Cesium's engine and workers still load from a CDN, so an internet
connection is required. Airfield buildings and trees are decorative; ground
collision and respawn are enabled.

For **Real world** mode:
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
`server.py` it listens on `$PORT` and injects the key from the
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

## Audit and verification
- App startup and Sandbox no longer depend on Google loading successfully.
- Google scripts and tiles load only when their mode is requested; search, presets,
  and location-based flights remain available.
- Saved flights retain their environment; older recordings default to Google.
- Fixed replay clock starting before scenery finished loading, score submission
  errors appearing on the wrong screen, input capture in text fields, and time
  formatting producing `:60`. Restored Performance graphics settings.
- Scores reject malformed/non-finite values and invalid paths; requests are size
  limited. Private repository files and raw score storage are not served.
- Scores are still client reported, not cheat resistant. Flight paths retain the
  existing 800-point recording limit (about 6 minutes 40 seconds).

Run API regression tests with `python3 -m unittest discover -s tests -v`.
With Python Playwright and Chromium installed, run `python3 tests/browser_smoke.py`
for Google-blocked Sandbox course, replay, mobile, and mode-switch checks.
The scene uses Cesium's [Viewer](https://cesium.com/learn/cesiumjs/ref-doc/Viewer.html)
and [polyline entities](https://cesium.com/learn/cesiumjs/ref-doc/PolylineGraphics.html).

## Flight planner
The original airplane is the only aircraft. Select a destination, then press
**Take off**. Real world is the default; Sandbox is an optional practice mode.
Controls and the leaderboard are in expandable sections. **C** or **View** changes
the flight camera. The original chase distance and flight physics are retained.
Older recordings with removed aircraft use the original airplane.

The engine loads on demand, and flight waits for the airplane to finish loading.
Static resources revalidate after deployment. Mobile flight actions remain visible.
Run `python3 tests/navigation_smoke.py` for menu, launch, model and mobile checks.

## Personal journeys
- **Logbook & journal** stores up to 60 flights/photos on the current browser and
  device. Records include duration, distance, a schematic track, discovered places,
  favorites and a route to revisit. Entries can be deleted or exported as JSON;
  photos can be downloaded. Storage failures are reported, not silently ignored.
- **Plan & flight conditions** adds optional destination bearings and distance,
  cruise-time estimates, a short local tour, daylight/sunrise/sunset, haze/rain,
  gentle air motion and opt-in radio announcements. Weather is a visual preset,
  not live conditions; photographed real-world shadows remain in the source imagery.
- **Sandbox runway start** begins stationary at Meadow Airfield. Increase throttle
  with Shift or the touch lever; hold W/up at 105 km/h to rotate. Land aligned with
  the strip, below 173 km/h, under 4 m/s descent, with wings close to level. Reduce
  throttle to brake; Finish saves the flight. Unsafe contacts and runway excursions
  respawn airborne. Uncheck runway start for the previous airborne practice mode.
  Real-world flights retain their airborne starts; city scenery is not a runway.
- **Return** guides you back to the departure point. **H / Hide HUD** removes
  secondary instruments while retaining warnings, guidance, touch controls and
  map credits. **P / Save photo** adds a picture to your travel journal.
- Flight audio adds engine pitch and volume tied to throttle, wind and runway
  rumble. Radio uses the browser's speech voice and is off by default.

Run `python3 tests/journey_smoke.py` for route calculations, browser persistence,
runway state transitions, weather rendering, minimal view and photo/logbook flows.
