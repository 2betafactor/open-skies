// Aircraft share the original flight physics; selection changes the model.
const PLANE_PARAMS = {
  mass: 1100, wingArea: 16, maxThrust: 2600, cd0: 0.03, kInduced: 0.05, clMax: 1.45,
  maxRollRateDeg: 80, maxPitchRateDeg: 40, turnFactor: 0.7,
  cruiseKmh: 180, minSpeedKmh: 50, maxSpeedKmh: 340,
  camBack: 40, camUp: 12, camRollFollow: 0, flapForce: 0,
};
export const VEHICLES = [
  { id: "skylark", emoji: "✈️", name: "Skylark", type: "plane", uri: "assets/skylark.glb", scale: 1, yaw: 0, pitch: 0, roll: 0, params: PLANE_PARAMS },
  { id: "swift", emoji: "🛩️", name: "Swift", type: "plane", uri: "assets/swift.glb", scale: 1, yaw: 0, pitch: 0, roll: 0, params: PLANE_PARAMS },
  { id: "plane", emoji: "✈️", name: "Classic", type: "plane", uri: "assets/plane.glb", scale: 0.09, yaw: -105, pitch: 0, roll: 0, params: PLANE_PARAMS },
];
