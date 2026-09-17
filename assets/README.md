# Open Skies aircraft

`skylark.glb` and `swift.glb` are original procedural aircraft made for this game.
They are self-contained glTF 2.0 binary files with smooth shaded fuselages, sampled
airfoil wings, cockpit glazing and frames, angled struts, tricycle landing gear,
and an animated propeller. Static surfaces are batched by material with indexed
geometry: two scene nodes and seven rendering primitives per aircraft. No texture
service, downloaded model, or additional runtime library is needed.

- Skylark: ivory and teal high-wing trainer, 10.8 m wingspan.
- Swift: ivory and red low-wing sport plane, 9.4 m wingspan.
- Classic: the pre-existing `plane.glb`, retained as a selectable aircraft and the
  default for older replays. Its original provenance is unchanged.

Rebuild the new assets with `python3 tools/build_aircraft.py`.
Coordinates: +X forward, +Y up, +Z right; units are metres. Cesium mounting uses
scale 1 and yaw 0 degrees. Both new aircraft retain the original flight physics.

The refined models are approximately 76 KB each, about 32% smaller than their
previous versions despite the additional surface detail.
