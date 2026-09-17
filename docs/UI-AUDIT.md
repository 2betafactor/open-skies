# Current UI and navigation

- One original airplane with external cameras; no aircraft or environment picker.
- Destination selection is explicit; Take off launches. Pending search text disables
  launch until the user selects a result or preset. Mobile actions remain reachable.
- Keeps logbook, photos, favorites, route planning, discovery notes, engine/wind
  audio, visual weather presets and minimal HUD with visible warnings and credits.
- Removed the generated practice scenery, runway controls, ground handling and
  associated code. Real-world flight keeps its original airborne start.
- New API submissions reject retired environments. Historical journal entries are
  preserved for viewing/export, without a broken revisit button. Old shared links
  explain that their environment is retired before any 3D engine loads.
- Versioned script/style URLs avoid mixing this UI with cached earlier builds.

Validation: API, menu/mobile navigation, preferences and journal operations, retired
replay links, and real-world launch/model/weather/photo flow with the external tile
provider stubbed. Live scenery coverage and account permissions are not verified by
these tests. Browser-local history caps at 60 entries; recorded paths at 800 points.
