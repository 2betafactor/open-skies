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
