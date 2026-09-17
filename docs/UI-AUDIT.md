# Hangar UI audit

## Findings and changes

- **Aircraft were hidden behind identical icons.** The home page now displays
  large previews rendered from the exact playable GLB assets. Skylark, Swift, and
  Classic have distinct thumbnails; Swift has red wings as well as its low-wing
  silhouette. Aircraft inspection loads those same GLBs in an interactive viewer.
- **Selecting a destination launched before aircraft selection was reviewed.**
  Destinations now select a route. A separate Take off button shows the selected
  destination and aircraft. Unconfirmed search text disables takeoff until a
  suggestion or preset is selected. Real world remains the default.
- **Returning users could receive cached presentation files.** Static files now
  require cache revalidation. Entry scripts, module imports, styles, models, and
  previews also use versioned URLs to avoid mixing old and new releases.
  The footer identifies this interface as Hangar / 03.
- **The menu depended on a large 3D engine download.** The engine now loads when
  flying, replaying, or opening 3D inspection. Browsing the menu and aircraft
  images works even when the engine request is blocked.
- **Flight could start before the aircraft finished loading.** Takeoff and replay
  now wait for the model's bounding sphere to become available, with a timeout
  and cancellation handling. A failed launch stops the hidden renderer.
- **Aircraft choice was not retained.** A validated aircraft ID is saved locally.
  The same ID is used for the preview, flight model, and existing replay metadata.
- **A direct rear camera made the aircraft hard to distinguish.** The chase
  camera is closer; C or the View button switches to a three-quarter profile view.
  The in-flight status includes the aircraft name.
- **Flight tuner opened while typing G in search.** Its shortcut now ignores text
  fields and only operates on the flight screen.
- **Old preset hover text still implied immediate flight.** Removed the inherited
  Fly pseudo-element. Home styles live in a dedicated, scoped stylesheet.

- **Flight actions overflowed narrow screens.** The HUD now uses separate
  instrument and action rows below 760 px, keeping View and Land reachable.

## Validation

- API and GLB structural tests, including static-cache headers.
- Menu with the 3D engine blocked; preview loading; aircraft persistence; route
  selection and unconfirmed search handling; desktop and mobile layouts.
- Actual GLB rendering in inspection, rotation, and viewer disposal on close.
- Selected Swift model ready before control is handed over; profile-camera toggle.
- Both new aircraft rendered in flight; spawn/recovery; simulation time; idle
  renderer behavior; Sandbox course progression and saved replay playback.

The checks use a browser and temporary server data. They do not verify external
scenery coverage or the production account's API permissions. Scores remain
client reported, and recordings retain the existing 800-point limit.
