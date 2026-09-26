# ✈️ Open Skies

Fly a plane over **photorealistic 3D of the real world** — search any location (or
pick a preset) and take off over Google's Photorealistic 3D Tiles, rendered with
**CesiumJS**. Finish a flight to post your **distance flown** to a shared **leaderboard**, and
every flight is **recorded** so you can share a link that **replays** it.

Vanilla HTML/CSS/JS front end + a tiny Python standard-library server (static files
+ leaderboard API). No build step, no framework, no third-party Python packages.

## Features
- Free-flight arcade model over real 3D terrain, with chase / cockpit / profile
  cameras, mouse free-look, HUD (airspeed / altitude / heading / throttle),
  engine + wind audio, and a golden-hour look.
- **Beginner & Aerobatic assist modes** — Beginner auto-levels and guards the
  floor; Aerobatic frees the attitude for full loops, barrel rolls and
  sustained inverted flight (the flight path really flies the maneuver). A
  **LEVEL** recovery button (`L`) rights the plane from any attitude, and a
  sensitivity slider tunes control response.
- **Animated control surfaces** — ailerons, elevator and rudder (elevons on the
  Wayfarer) deflect with your inputs on the glTF models.
- **Ring Run activity** — an optional checkpoint course of glowing rings with a
  timer; free flight stays the default.
- **Graphics toggle** — Performance / Balanced / Quality (photorealistic tiles are
  GPU-heavy; pick your trade-off).
- **Leaderboard** ranked by distance flown, with medals.
- **Flight recording + shareable replays** — `/?flight=<id>` replays a saved flight.

## Controls
`W/S` pitch · `A/D` roll · `Q/E` rudder · `Shift/Ctrl` throttle · `Space` hold
level · `L` recover · `B` assist mode · `R` loop · `T` barrel roll · `C` camera
· drag with the mouse to look around · `Esc` / **Finish** to finish.

## Run locally
Run `python3 server.py` and open http://localhost:8000. **Real world** is the
default, with the original location search, presets, and real-world flights.
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
Production serving runs `python3 serve.py` (see `Procfile`), which serves the
WSGI app in `wsgi.py` through **waitress** (`requirements.txt`) — Python's docs
advise against exposing the stdlib `http.server` publicly, and `serve.py` falls
back to it only for dependency-free local dev. The app listens on `$PORT` and
injects the key from the `GOOGLE_MAPS_API_KEY` env var into `/config.js`, so
**the key never lives in the repo**. Leaderboard scores are written to
`$DATA_DIR` (mount a persistent volume there so they survive redeploys).

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

## Flight planner and personal journeys
Choose **Aerion**, a detailed twin-engine jet, or **Wayfarer**, a fictional
spaceship for atmospheric exploration. Select a real-world destination and
press **Take off**. Flights start airborne. There is no environment selector or
practice airfield.

- **Route guidance** offers optional destinations, distance and cruise-time
  estimates, while local digital radio can find nearby stations after location
  permission and lets you switch or stop playback.
- **Return** guides you back to departure. **H / Hide HUD** hides secondary
  instruments while retaining warnings, navigation, touch controls and credits.
- **P / Save photo** adds an image to the travel journal. **Finish** saves flight
  duration, distance, discoveries and a schematic route to your logbook.
- **Logbook & journal** retains up to 60 entries on this browser/device, with
  favorites, route revisiting, photo downloads, JSON export and entry deletion.
  Storage failures are reported. Recordings retain the existing 800-point limit.
- Engine sound responds to throttle and wind to speed. Radio playback is optional
  and stays off until the player chooses a station.
- Records from retired environments remain readable/exportable in the journal,
  but cannot be launched. Shared links for retired flights explain their status
  and return to destination selection. New scores accept real-world flights only.

## Verification
Run `python3 -m unittest discover -s tests -v` for API and asset-access checks.
With Python Playwright/Chromium installed, run:

- `python3 tests/navigation_smoke.py`: destination selection and mobile menu.
- `python3 tests/journal_menu_smoke.py`: preferences, revisit, export, deletion,
  and storage-failure handling.
- `python3 tests/browser_smoke.py`: retired replay and archived-journal handling.
- `python3 tests/journey_smoke.py`: real-world launch contract, selected GLB
  rendering, weather, minimal view, photo capture and logbook persistence. The
  external tile provider is stubbed in this check; production imagery coverage
  and API permissions require a configured live account.

Static files revalidate after deployment. The engine loads on demand and flight
waits for the airplane model. Scores remain client reported, not cheat resistant.

## Aircraft and review fixes
Aerion has curved cockpit glazing, cabin windows, swept airfoil wings, winglets,
recessed engine fans and smoother jet handling. Wayfarer has an armored hull,
ion emitters, faster assisted steering and a distinct engine tone. It flies over
Earth; no space environment or cockpit has been added. Both use the same controls;
F/flaps and V/force-based simulation apply only to the airplane.

Aircraft choice persists, and recorded flights and personal journeys retain it.
Old airplane recordings use the upgraded jet. The original `plane.glb` remains
in the repository. See `assets/README.md` for reproducible geometry and previews.
Run `python3 tests/fleet_smoke.py` to validate both models, orientation, handling
reset, saved selection and spaceship replay. See `docs/UI-AUDIT.md` for review
findings, including replay cleanup/date-line fixes and low-score share retention.
