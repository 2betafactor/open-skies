# ✈️ Open Skies

Fly a plane over **photorealistic 3D of the real world** — pick any place on
Earth and take off over Google's Photorealistic 3D Tiles.

**Open Skies now runs on the Godot 4.7 engine** (the `godot/` project) with a
real six-degree-of-freedom flight model and fly-by-wire assists, streamed
Google 3D Tiles, animated control surfaces, Nightride FM under the engine
noise, and the shared distance leaderboard. The original CesiumJS version is
still served at `/classic`.

## Godot version (default at `/`)

- **Arcade by default** — point and go: wings level themselves, the engine
  manages itself (hold `Shift` for boost, `Space` to brake), no stalls, and a
  **Ring Run** course of glowing rings laid out ahead of you with score and
  combos. Loops (`R`) and barrel rolls (`T`) score bonus points. Switch to
  *Pro* for the full fly-by-wire (neutral stick holds altitude through turns,
  auto-coordinated rudder, angle-of-attack and G limiters) or *Sim* for raw
  control surfaces (`B` cycles).
- **Flight model** — six-degree-of-freedom: lift/drag with a soft stall,
  moments from stability derivatives, throttle spool, altitude-dependent air
  density, trimesh collision against the streamed city.
- **Four aircraft** — Typhoon (canard-delta fighter), Tomcat (swing wings
  that sweep back with speed), Sabre (1950s classic) and Nova (vectored-thrust
  scout ship), each with its own mass, aerodynamics, thrust and engine sound.
- **World** — `godot/scripts/tiles.gd` streams Google Photorealistic 3D Tiles
  in pure GDScript: a full bubble around the spawn is preloaded before
  takeoff, a look-ahead bubble prefetches where you are heading, decoding is
  budgeted per frame, and the tiles around the aircraft carry collision.
- **Mobile** — touch controls (virtual stick, boost/brake slider, buttons),
  UI that scales with the screen, and lighter tile settings on phones.
- **Cameras** — chase (spring-damped, partial roll follow, mouse orbit),
  cockpit, and fly-by (`C`). HUD with pitch ladder, heading tape, flight-path
  marker, speed/altitude/AGL, boost, score and a pointer to the next ring.
- **Music** — Nightride FM streams on takeoff (`M` toggles) on top of the
  procedural engine/wind layer.
- **Leaderboard** — finish a flight from the pause menu (`Esc`) to post your
  distance to the shared board.

### Controls
`W/S` pitch · `A/D` roll · `Q/E` rudder · `Shift/Ctrl` throttle · `Space` air
brake · `L` level · `B` assist · `R` loop · `T` barrel roll · `C` camera ·
`H` HUD · `M` radio · drag the mouse to look around · `Esc` pause / finish.
Gamepads work too (left stick, bumpers for rudder, triggers for throttle).

### Build & run
```bash
# one-time: Godot 4.7.2 editor + export templates
mkdir -p ~/godot && cd ~/godot
wget https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip && unzip Godot_v4.7.2-stable_linux.x86_64.zip
wget https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
mkdir -p ~/.local/share/godot/export_templates/4.7.2.stable && cd ~/.local/share/godot/export_templates/4.7.2.stable && unzip ../../../godot/Godot_v4.7.2-stable_export_templates.tpz && mv templates/* . && rmdir templates

# export the web build into play/ (served at /), or desktop builds into dist/
godot/build.sh web        # also: linux | windows | all
python3 server.py         # http://localhost:8000
```
The web build reads the Google key from `/api/config` (env `GOOGLE_MAPS_API_KEY`
or `config.js`) and geocodes searches through `/api/search`, so the key never
ships in the client bundle. Desktop builds talk to the hosted server by
default; pass `--server=https://your.host` or `--key=AIza…` to override.
Query-string overrides on the web: `?quality=Performance&scale=0.5`.

### Credits
Aircraft: Typhoon, Tomcat and Sabre are from the CC0 "fighter jets" pack on
[OpenGameArt](https://opengameart.org/node/146570) (re-skinned here); Nova is
the CC0 "Spaceship" by [Quaternius](https://quaternius.com). Map data:
Google Photorealistic 3D Tiles (attribution shown in-game, as required).
Music: [Nightride FM](https://nightride.fm).

### Tests
```bash
godot/tests: godot --headless --path godot tests/flight_test.tscn -- --vehicle=aerion   # physics + fly-by-wire
             godot --headless --path godot tests/tile_test.tscn                        # tile streaming (network)
godot --headless --path godot -- --server=http://localhost:8000 --autostart=1 --trace=1 --seconds=30
python3 tests/godot_web_smoke.py   # plays the exported web build in headless Chromium (slow: software GL)
```

## Classic (CesiumJS) version — `/classic`

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
