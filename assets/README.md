# Open Skies fleet

- `aerion.glb`: original twin-engine touring jet with smooth lofted fuselage,
  swept airfoil wings/winglets, curved glazing, cabin window surrounds, engine
  nacelles, recessed fan blades, exhausts, navigation lights and livery.
- `wayfarer.glb`: original fictional atmospheric spaceship, with swept armor,
  smoked canopy, canted fins, twin ion emitters and warning markings.
- `plane.glb`: previous model, retained in the repository as the original asset.

Build with `python3 tools/build_fleet.py` (Python standard library). The models
use glTF 2.0 +Y up/+Z forward; Cesium mount yaw is -90 degrees, scale 1 metre.
Static geometry is indexed and batched by material: seven draws for Aerion,
six for Wayfarer, before any renderer passes. No external textures or mesh services.
Aerion is approximately 413 KB; Wayfarer approximately 116 KB.

`*-preview.png` are transparent renders of these exact GLBs, generated using
`python3 tools/render_fleet.py` (Python Playwright/Chromium and internet required).
