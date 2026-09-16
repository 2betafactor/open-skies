# Open Skies aircraft

`skylark.glb` and `swift.glb` are original procedural aircraft made for this game.
They are self-contained glTF 2.0 binary files with material colors, cockpit glazing,
shaped wings and fuselages, landing gear, and an animated propeller. No texture
service, downloaded model, or additional runtime library is needed.

- Skylark: ivory and teal high-wing trainer, 10.8 m wingspan.
- Swift: ivory and red low-wing sport plane, 9.4 m wingspan.
- Classic: the pre-existing `plane.glb`, retained as a selectable aircraft and the
  default for older replays. Its original provenance is unchanged.

Rebuild the new assets with `python3 tools/build_aircraft.py`.
Coordinates: +X forward, +Y up, +Z right; units are metres. Cesium mounting uses
scale 1 and yaw 0 degrees. Both new aircraft retain the original flight physics.

`street-gt.glb` is the original orange GT coupe for Street Run: sculpted body,
glass canopy, mirrors, wheels, spoiler, and front/rear lights. Rebuild it with
`python3 tools/build_car.py`. It uses the same metre-based coordinate convention
as the aircraft and contains no external textures.
