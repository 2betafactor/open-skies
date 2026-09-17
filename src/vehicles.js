// Aircraft share the original flight physics; selection changes the model.
const PLANE_PARAMS = {
  mass: 1100, wingArea: 16, maxThrust: 2600, cd0: 0.03, kInduced: 0.05, clMax: 1.45,
  maxRollRateDeg: 80, maxPitchRateDeg: 40, turnFactor: 0.7,
  cruiseKmh: 180, minSpeedKmh: 50, maxSpeedKmh: 340,
  camBack: 24, camUp: 6, camRollFollow: 0, flapForce: 0,
};
export const VEHICLES = [
  { id: "skylark", emoji: "✈️", name: "Skylark", description: "High-wing touring aircraft", spec: "10.8 m wingspan · single engine", type: "plane", uri: "assets/skylark.glb?v=3", scale: 1, yaw: 0, pitch: 0, roll: 0, params: PLANE_PARAMS },
  { id: "swift", emoji: "🛩️", name: "Swift", description: "Low-wing sport aircraft", spec: "9.4 m wingspan · single engine", type: "plane", uri: "assets/swift.glb?v=3", scale: 1, yaw: 0, pitch: 0, roll: 0, params: PLANE_PARAMS },
  { id: "plane", emoji: "✈️", name: "Classic", description: "The original Open Skies plane", spec: "Familiar handling · classic model", type: "plane", uri: "assets/plane.glb", scale: 0.09, yaw: -105, pitch: 0, roll: 0, params: PLANE_PARAMS },
];
