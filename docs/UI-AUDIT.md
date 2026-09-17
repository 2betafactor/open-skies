# UI and navigation audit

- Restored the original airplane as the only model, with its original chase camera.
  Removed alternate assets, aircraft selection, stored selection handling and inspection.
  Older recordings fall back to the original airplane.
- Simplified the home page to a destination planner with explicit Take off.
  Real world remains the default; Sandbox remains secondary.
- Selecting a preset does not launch. Unconfirmed search text disables Take off.
- Kept lazy engine loading, model readiness checks, cancellation and cache revalidation.
- Preserved mobile HUD wrapping, keyboard input guards, help and expandable leaderboard.
  Increased home text and control sizes and restored browser zoom.

Validation: API regression suite and browser navigation / Sandbox smoke checks.
Browser checks block the external map provider; production scenery and API permissions
are outside their scope. Scores remain client reported and recordings cap at 800 points.

## Personal journey update
- Keeps the original airplane and external cameras; adds no cockpit or vehicle picker.
- Flight options are collapsed by default, preserving the simple destination-first menu.
- Adds device-local logbook/photos, route guidance and return-to-departure, destination
  discovery notes, minimal HUD, synthesized engine/ground audio and opt-in speech.
- Adds optional Sandbox runway starts and stable touchdown/braking. Real-world
  takeoff stays airborne because arbitrary searched locations are not safe runways.
- Adds visual time/weather presets and optional gentle motion. Clear daylight is
  the default; motion can be disabled; radio starts off. No live-weather claims.
- Storage writes report failures; entries can be deleted, favorited, downloaded or
  exported. The journal retains at most 60 entries and is specific to this browser.
- Minimal HUD retains warnings, route guidance, touch inputs, credits and Show HUD.
- Photos preserve visible source attribution in exported images.
