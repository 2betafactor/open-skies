# Current UI and navigation

- A touring jet and spaceship with external cameras; no environment picker.
- Destination selection is explicit; Take off launches. Pending search text disables
  launch until the user selects a result or preset. Mobile actions remain reachable.
- Keeps logbook, photos, favorites, route planning, discovery notes, engine/wind
  audio, optional local digital radio and a minimal HUD with visible warnings and credits.
- Removed the generated practice scenery, runway controls, ground handling and
  associated code. Real-world flight keeps its original airborne start.
- New API submissions reject retired environments. Historical journal entries are
  preserved for viewing/export, without a broken revisit button. Old shared links
  explain that their environment is retired before any 3D engine loads.
- Versioned script/style URLs avoid mixing this UI with cached earlier builds.

Validation: API, menu/mobile navigation, preferences and journal operations, retired
replay links, and real-world launch/model/photo flow with the external tile
provider stubbed. Live scenery coverage and account permissions are not verified by
these tests. Browser-local history caps at 60 entries; recorded paths at 800 points.

## Fleet review — 2026-09-18

- Replaced the visible legacy airplane with an original detailed twin-engine jet;
  added one fictional spaceship. Kept real-world scenery and external views only.
- Two compact model previews provide an explicit choice, retained across reloads.
  Old/invalid selections fall back to the airplane. Replay IDs, score submissions,
  local logbook entries and journey revisiting carry the chosen aircraft.
- Jet handling now has slower thrust response, more rotational inertia and moderate
  roll/pitch rates. Force-based simulation remains optional. Spaceship uses faster
  assisted handling and ignores airplane-only flap/simulation keys.
- Corrected model export axes to glTF +Z forward, and fitted windshield geometry
  to the curved fuselage to eliminate intersections. Both models use indexed
  geometry, shared materials and no texture downloads. Asset tests validate buffers,
  bounds, normal lengths, indices and model size.
- Fixed replay interpolation across the international date line; longitudes now
  follow the short crossing rather than jumping across the globe.
- Journal route sketches now handle date-line crossings and fit/center their tracks.
- Failed replay cleanup now stops the hidden render loop.
- Corrected HUD heading rounding from 360° to 0°.
- Made the advertised Space/level-wings control override roll input in both flight
  modes; airplane flaps now also reduce arcade target speed.
- Fixed new low-score share links being immediately discarded at the 300-record
  limit. Storage now retains the best 299 older flights plus the new flight.
- Route duration estimates now use the selected aircraft's cruise speed. Camera
  button text is resynchronized when entering another flight.

Checks cover menu/mobile layout, persistence/export, API validation/share retention,
retired environment handling, both GLBs rendered in flight, mount orientation,
parameter resets, spaceship replay and date-line crossing. External map tiles are
stubbed in rendering tests; live coverage/API permissions and device FPS are not
measured. Handling is accessible arcade flight by default, not certified simulation.
