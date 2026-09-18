// Original geometry, distinct handling, and consistent IDs across flights/replays.
export const VEHICLES = [
  { id: "plane", name: "Aerion", description: "Twin-engine touring jet", type: "plane",
    uri: "assets/aerion.glb?v=fleet7", preview: "assets/aerion-preview.png?v=fleet7", scale: 1, yaw: -90, pitch: 0, roll: 0,
    params: { mass: 5200, wingArea: 28, maxThrust: 18000, cd0: .026, kInduced: .045, clMax: 1.5,
      cruiseKmh: 240, minSpeedKmh: 100, maxSpeedKmh: 460, maxRollRateDeg: 48, maxPitchRateDeg: 24,
      turnFactor: .48, throttleLag: 3.2, rotEase: 4.5, velLag: .65, camBack: 34, camUp: 10, camTau: .3, flapForce: 0 } },
  { id: "spaceship", name: "Wayfarer", description: "Ion-powered atmospheric explorer", type: "spaceship",
    uri: "assets/wayfarer.glb?v=fleet7", preview: "assets/wayfarer-preview.png?v=fleet7", scale: 1, yaw: -90, pitch: 0, roll: 0,
    params: { cruiseKmh: 300, minSpeedKmh: 40, maxSpeedKmh: 720, maxRollRateDeg: 90, maxPitchRateDeg: 48,
      turnFactor: .85, throttleLag: 1.3, rotEase: 7, velLag: .18, energyFactor: 0, turnBleed: .025,
      camBack: 32, camUp: 10, camTau: .24, flapForce: 0 } },
  { id: "cyberwing", name: "Cyberwing", description: "Neon stealth interceptor", type: "plane",
    uri: "assets/cyberwing.glb?v=cyber1", preview: "assets/cyberwing-preview.png?v=cyber1", scale: 1, yaw: -90, pitch: 0, roll: 0,
    params: { mass: 3400, wingArea: 24, maxThrust: 15000, cd0: .024, kInduced: .04, clMax: 1.55,
      cruiseKmh: 280, minSpeedKmh: 110, maxSpeedKmh: 620, maxRollRateDeg: 65, maxPitchRateDeg: 30,
      turnFactor: .52, throttleLag: 2.2, rotEase: 5.5, velLag: .35, camBack: 30, camUp: 9, camTau: .26, flapForce: 0 } },
];
