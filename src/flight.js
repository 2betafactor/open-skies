// flight.js — arcade flight engine over Google Photorealistic 3D Tiles (Cesium).
// Implements the "feel guide" reference model: rotational inertia, energy
// exchange, velocity-lag, input shaping, spring auto-level, fixed 120 Hz step.
// Every feel constant lives in `this.P` and is exposed to the live tuner panel.

const PLANE_URI = "assets/plane.glb";
const PLANE_SCALE = 0.15; // wingspan ~92 units → ~14 m
const D2R = Math.PI / 180;
const STEP = 1 / 60; // physics substep (halves per-frame work vs 1/120)

const FLOOR_WARN = 25; // m AGL
const FLOOR_CRASH = 6;
const CEILING_AGL = 4000; // "thin air" measured above local terrain
const SPAWN_AGL = 350; // metres ABOVE local terrain (works over canyon/alps too)

// The GLB's authored forward axis doesn't match our travel axis. The corrective
// rotation is applied ONCE here from tunable offsets (P.modelYawDeg/Pitch/Roll) —
// physics never touches it. Adjust the three "model …" sliders until the nose
// points down the travel direction and the wings sit level.

// Reference parameter set (human units; converted in physics).
export const DEFAULT_PARAMS = {
  minSpeedKmh: 50,
  cruiseKmh: 180,
  maxSpeedKmh: 340,
  maxRollRateDeg: 80,
  maxPitchRateDeg: 40,
  rudderRateDeg: 25,
  rotEase: 8, // higher = snappier rotation
  energyFactor: 0.45, // dive→fast, climb→slow
  turnFactor: 0.7, // yawRate = sin(roll)*turnFactor
  turnBleed: 0.05, // speed lost in turns
  velLag: 0.4, // s, velocity eases toward nose (drift through turns)
  throttleLag: 1.5, // s, engine response
  autoFreq: 2.2, // auto-level spring frequency
  autoDamp: 0.6, // <1 → slight wing-rock overshoot
  pitchClampDeg: 60,
  rollClampDeg: 80,
  ambientDeg: 0, // idle air drift (0 = perfectly steady; raise for life)
  // Static model-mount correction — measured live: -105° flies the nose straight.
  modelYawDeg: -105,
  modelPitchDeg: 0,
  modelRollDeg: 0,
  // --- realistic (sim) model: Cessna-172-ish ---
  mass: 1100, // kg
  wingArea: 16, // m²
  maxThrust: 2600, // N
  cd0: 0.03,
  kInduced: 0.05,
  clMax: 1.45, // CL at ~15° AoA (clean)
  trimAoADeg: 2.5, // AoA the plane settles toward hands-off
  weathervane: 2.2, // how strongly the nose follows velocity
  pitchStab: 1.4,
  rollDamp: 2.2,
  flapForce: 0, // N per flap (bird only)
  camBack: 40, // metres behind (was 13 — plane filled the whole screen)
  camUp: 12,
  camTau: 0.16,
  camLookAhead: 8,
  camRollFollow: 0, // 0 = horizon stays level (no camera bank); raise for drama
  fovMinDeg: 62,
  fovMaxDeg: 78,
};

export class Flight {
  constructor(containerId) {
    this.containerId = containerId;
    this.viewer = null;
    this.tileset = null;
    this.plane = null;
    this.onError = () => {};
    this.onState = () => {};
    this.P = { ...DEFAULT_PARAMS };

    // Selected vehicle (model + mount correction). Default = the plane.
    this._uri = PLANE_URI;
    this._scale = PLANE_SCALE;
    this.vehicleType = "plane"; // "plane" | "heli" | "balloon"
    this._quality = "performance"; // graphics level; default to playable

    this.controls = { pitch: 0, roll: 0, rudder: 0, throttle: 0, level: false };

    this.position = null;
    this.orientation = null;
    this.heading = 0;
    this.pitch = 0;
    this.roll = 0;
    this.speed = 50 / 3.6;
    this.throttle = 0.5;
    this.propAngle = 0;
    this.crashes = 0;
    this.distance = 0; // km flown this flight (leaderboard score)
    this.topSpeedKmh = 0;
    this._flightStart = 0;
    this.path = []; // recorded flight plan: [lng, lat, alt, headingRad] every 0.5 s
    this._pathAcc = 0;
    this._recording = null; // when replaying: the path array
    this._recStart = 0;
    this._recDur = 0;
    this.onReplayEnd = () => {};
    const PATH_DT = 0.5;
    this._pathDt = PATH_DT;
    // Sim model
    this.mode = "arcade"; // "arcade" | "sim" — toggle with V
    this.velocity = null; // Cartesian3 (ECEF), sim mode
    this.flaps = 0; // 0 | 20 | 40 degrees
    this._thrustN = 0;
    this._aoa = 0;
    this._vspeed = 0;
    this._stall = false;
    this._lastFlap = 0;
    this._flapUntil = 0;
    this.agl = 9999;
    this.alt = SPAWN_AGL;
    this.warning = "";
    this.spawnLL = null;
    this.spawnGround = 0;
    this._marker = null; // "you are here" beacon
    this._targetLL = null;

    this._rollVel = 0;
    this._pitchVel = 0;
    this._velDir = null;
    this._camPos = null;
    this._lastT = 0;
    this._acc = 0;
    this._t = 0;
    this._groundAcc = 0;
    this._logAcc = 0;
    this._stateAcc = 0;
    this._aglBuf = [];
    this._aglFilt = 9999;
    this._lowSince = 0;
    this._groundValid = false;
    this._graceUntil = 0;
    this._pullUntil = 0;
    this._running = false;
    this._preUpdate = null;
    this._warned = false;
  }

  async init(key) {
    const C = window.Cesium;
    C.Ion.defaultAccessToken = undefined;
    this.viewer = new C.Viewer(this.containerId, {
      baseLayer: false,
      baseLayerPicker: false,
      geocoder: false,
      homeButton: false,
      sceneModePicker: false,
      navigationHelpButton: false,
      fullscreenButton: false,
      timeline: false,
      animation: false,
      infoBox: false,
      selectionIndicator: false,
      requestRenderMode: false,
    });
    const scene = this.viewer.scene;
    scene.renderError.addEventListener((s, e) => {
      console.error("Cesium render error:", e);
      this.onError(e);
    });
    scene.globe.show = false;
    scene.skyAtmosphere.show = true; // blue sky (not black)
    scene.skyBox.show = false; // daytime — no starfield
    scene.backgroundColor = C.Color.fromCssColorString("#8fbce8"); // sky blue fallback
    scene.fog.enabled = true;
    scene.fog.density = 0.0001; // light haze (less culling for quality)
    scene.screenSpaceCameraController.enableInputs = false;
    this.viewer.clock.shouldAnimate = true;

    // --- Performance ---
    this.viewer.useBrowserRecommendedResolution = true; // cap retina (big perf win)
    logGPU(); // GPU model → console only (panel removed)
    // Warm, low "golden hour" sun — richer mood, lights the plane nicely.
    scene.light = new C.DirectionalLight({
      direction: C.Cartesian3.normalize(new C.Cartesian3(0.5, -0.32, -0.8), new C.Cartesian3()),
      color: new C.Color(1.0, 0.9, 0.72),
      intensity: 2.4,
    });

    this.tileset = await createGoogleTileset(C, key);
    // Perf: coarser tiles = far less geometry to stream + draw. 16 is the default
    // (very heavy); 32 is much lighter and still fine at altitude.
    // Streaming/cache: keep loaded tiles resident so re-flying an area doesn't
    // re-stream. cullRequestsWhileMoving stays TRUE (Cesium default) — easing off
    // tile requests during fast flight avoids the periodic decode hitches that
    // read as the plane "lugging"/surging.
    this.tileset.cacheBytes = 768 * 1024 * 1024;
    this.tileset.maximumCacheOverflowBytes = 384 * 1024 * 1024;
    this.tileset.cullRequestsWhileMoving = true;
    this.tileset.foveatedScreenSpaceError = true;
    scene.primitives.add(this.tileset);
    this.setQuality(this._quality); // apply the selected graphics level
    return this;
  }

  async spawn(lat, lng, onProgress = () => {}, opts = {}) {
    const C = window.Cesium;
    this._teardown();

    const sLat = lat;
    const sLng = lng;
    this._targetLL = null;
    this.spawnLL = { lat: sLat, lng: sLng };
    this.heading = 0;
    this.pitch = 0;
    this.roll = 0;
    this._rollVel = 0;
    this._pitchVel = 0;
    this._velDir = null;
    this._acc = 0;
    this._t = 0;
    this.throttle = 0.5;
    this.speed = this.P.cruiseKmh / 3.6;
    this.crashes = 0;
    this._groundValid = false;
    this._aglBuf = [];
    this._lowSince = 0;
    this._graceUntil = performance.now() + 3000;
    this._setPositionLL(sLat, sLng, 3000); // provisional; corrected after ground sample
    this._recomputeOrientation();

    onProgress(0.4, "Spooling up the tiles…");
    // Look straight down from high above so tiles stream in regardless of terrain height.
    this.viewer.camera.setView({
      destination: C.Cartesian3.fromDegrees(sLng, sLat, 6000),
      orientation: { heading: 0, pitch: -1.45, roll: 0 },
    });
    await this._waitForTiles(25000, onProgress); // longer preload of the spawn area

    // Find the local ground so we can spawn ABOVE it (canyon/alps safe).
    this.spawnGround = 0;
    try {
      const carto = C.Cartographic.fromDegrees(sLng, sLat);
      const [res] = await this.viewer.scene.sampleHeightMostDetailed([carto]);
      if (res && isFinite(res.height)) this.spawnGround = res.height;
    } catch (e) {
      /* fall back to 0 */
    }
    this._setPositionLL(sLat, sLng, this.spawnGround + SPAWN_AGL);
    this._graceUntil = performance.now() + 3000;
    this._recomputeOrientation();

    // Sim state: start with velocity down the nose at cruise.
    this.flaps = 0;
    const b0 = this._basisFor(this.heading, this.pitch, this.roll);
    this.velocity = scale(b0.F, this.P.cruiseKmh / 3.6);
    this._thrustN = this.throttle * this.P.maxThrust;
    log(`ground ${Math.round(this.spawnGround)}m → spawn ${Math.round(this.spawnGround + SPAWN_AGL)}m`);

    this._addPlane();

    this._camHeading = this.heading;
    this.viewer.camera.frustum.fov = 60 * D2R; // fixed FOV (per-frame changes shimmer)
    this._installLoop();
    this._updateCamera(0);
    onProgress(1, "Cleared for takeoff.");
    log(`spawn ${lat.toFixed(4)},${lng.toFixed(4)}`);
  }

  _addPlane() {
    const C = window.Cesium;
    this.plane = this.viewer.entities.add({
      position: new C.CallbackProperty(() => this.position, false),
      orientation: new C.CallbackProperty(() => this.orientation, false),
      model: { uri: this._uri, scale: this._scale, minimumPixelSize: 64, runAnimations: false },
    });
  }

  // A glowing beacon + "YOU" label at the target location (fly-toward-me mode).
  _addMarker(lat, lng, baseAlt) {
    const C = window.Cesium;
    this._marker = this.viewer.entities.add({
      polyline: {
        positions: [
          C.Cartesian3.fromDegrees(lng, lat, baseAlt - 60),
          C.Cartesian3.fromDegrees(lng, lat, baseAlt + 950),
        ],
        width: 8,
        material: new C.PolylineGlowMaterialProperty({
          glowPower: 0.28,
          color: C.Color.fromCssColorString("#4fc3f7"),
        }),
      },
      position: C.Cartesian3.fromDegrees(lng, lat, baseAlt + 1010),
      label: {
        text: "📍 YOU",
        font: "bold 18px sans-serif",
        fillColor: C.Color.WHITE,
        showBackground: true,
        backgroundColor: C.Color.fromCssColorString("#0a0f0d").withAlpha(0.75),
        pixelOffset: new C.Cartesian2(0, -6),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    });
  }

  // ---- Replay a saved flight plan ----
  async startReplay(path, onProgress = () => {}) {
    const C = window.Cesium;
    this._teardown();
    if (!path || path.length < 2) throw new Error("This flight has no recorded path.");
    this.setVehicle({ uri: "assets/plane.glb", scale: 0.09, yaw: -105, type: "plane", params: {} });
    const [lng0, lat0, alt0, hdg0] = path[0];
    this.spawnLL = { lat: lat0, lng: lng0 };
    this.heading = hdg0 || 0;
    this.pitch = 0;
    this.roll = 0;
    this.position = C.Cartesian3.fromDegrees(lng0, lat0, alt0);
    this._recomputeOrientation();

    onProgress(0.4, "Loading flight…");
    this.viewer.camera.setView({
      destination: C.Cartesian3.fromDegrees(lng0, lat0, alt0 + 600),
      orientation: { heading: 0, pitch: -1.45, roll: 0 },
    });
    await this._waitForTiles(25000, onProgress);

    this._addPlane();
    this._camHeading = this.heading;
    this.viewer.camera.frustum.fov = 60 * D2R;
    this._recording = path;
    this._recDur = (path.length - 1) * this._pathDt;
    this._recStart = performance.now();
    this._installLoop();
    this._updateCamera(0);
    onProgress(1, "Playing.");
  }

  _stepReplay() {
    const C = window.Cesium;
    const path = this._recording;
    const elapsed = (performance.now() - this._recStart) / 1000;
    if (elapsed >= this._recDur) {
      this._recording = null;
      const cb = this.onReplayEnd;
      if (cb) cb();
      return;
    }
    const fi = elapsed / this._pathDt;
    const i = Math.min(path.length - 2, Math.floor(fi));
    const t = fi - i;
    const a = path[i];
    const b = path[i + 1];
    const lng = a[0] + (b[0] - a[0]) * t;
    const lat = a[1] + (b[1] - a[1]) * t;
    const alt = a[2] + (b[2] - a[2]) * t;
    this.position = C.Cartesian3.fromDegrees(lng, lat, alt);
    this.heading = a[3] + shortAngle(a[3], b[3]) * t;
    this.alt = alt;
    const pa = C.Cartesian3.fromDegrees(a[0], a[1], a[2]);
    const pb = C.Cartesian3.fromDegrees(b[0], b[1], b[2]);
    this.speed = C.Cartesian3.distance(pa, pb) / this._pathDt;
  }

  start() {
    this._running = true;
    this._lastT = 0;
    this.distance = 0;
    this.topSpeedKmh = 0;
    this.path = [];
    this._pathAcc = 0;
    this._flightStart = performance.now();
    log("takeoff");
  }

  getStats() {
    return {
      distanceKm: this.distance,
      timeSec: this._flightStart ? (performance.now() - this._flightStart) / 1000 : 0,
      topSpeedKmh: Math.round(this.topSpeedKmh),
    };
  }

  getFlight() {
    return { ...this.getStats(), path: this.path };
  }

  dispose() {
    this._teardown();
  }

  // Graphics level — the real FPS lever (draws fewer pixels + less tile geometry).
  setQuality(level) {
    this._quality = level || "performance";
    if (!this.viewer) return;
    const L = {
      performance: { res: 0.5, msaa: 1, fxaa: false, sse: 40, dyn: true, fog: 0.0004 },
      balanced: { res: 0.75, msaa: 1, fxaa: true, sse: 20, dyn: true, fog: 0.0002 },
      quality: { res: 1.0, msaa: 4, fxaa: true, sse: 8, dyn: false, fog: 0.0001 },
    }[this._quality];
    if (!L) return;
    const s = this.viewer.scene;
    s.msaaSamples = L.msaa;
    s.postProcessStages.fxaa.enabled = L.fxaa;
    s.fog.density = L.fog;
    s.highDynamicRange = this._quality !== "performance"; // richer colour/contrast
    this.viewer.resolutionScale = L.res;
    if (this.tileset) {
      this.tileset.maximumScreenSpaceError = L.sse;
      this.tileset.dynamicScreenSpaceError = L.dyn;
    }
    log("quality → " + this._quality);
  }

  // Choose which vehicle to fly (called before spawn).
  setVehicle(v) {
    // Reset to baseline first so one vehicle's params (e.g. the bird's 2.5 m
    // camera) never bleed into the next (the balloon had no params of its own).
    Object.assign(this.P, DEFAULT_PARAMS);
    this._uri = v.uri;
    this._scale = v.scale;
    this.vehicleType = v.type || "plane";
    this.P.modelYawDeg = v.yaw || 0;
    this.P.modelPitchDeg = v.pitch || 0;
    this.P.modelRollDeg = v.roll || 0;
    if (v.params) Object.assign(this.P, v.params);
    // Bird flies the force-based model (glide + flap); everything else arcade.
    this.mode = this.vehicleType === "bird" ? "sim" : "arcade";
    log("vehicle → " + this.vehicleType);
  }

  cycleFlaps() {
    this.flaps = this.flaps === 0 ? 20 : this.flaps === 20 ? 40 : 0;
    log("flaps " + this.flaps);
  }

  toggleMode() {
    if (this.mode === "arcade") {
      // Entering sim: seed the velocity vector from the current heading + speed.
      const b = this._basisFor(this.heading, this.pitch, this.roll);
      this.velocity = scale(b.F, this.speed);
      this._thrustN = this.throttle * this.P.maxThrust;
      this.mode = "sim";
    } else {
      this.speed = window.Cesium.Cartesian3.magnitude(this.velocity);
      this.mode = "arcade";
    }
    log("mode → " + this.mode);
  }

  // ---- fixed-step loop ----
  _installLoop() {
    this._preUpdate = () => {
      try {
        const now = performance.now();
        if (!this._lastT) this._lastT = now;
        let frameDt = (now - this._lastT) / 1000;
        this._lastT = now;
        if (frameDt > 0.1) frameDt = 0.1;

        // Camera FIRST — Cesium already evaluated the plane entity's position for
        // THIS frame (in clock.onTick, before preUpdate). Point the camera at that
        // SAME position, then advance physics for the NEXT frame. Doing it the other
        // way left the plane one physics-step behind the camera, and because frame
        // time jitters, that gap jittered → the trembling. This keeps them in sync.
        this._updateCamera(frameDt);

        if (this._recording) {
          this._stepReplay();
          this._recomputeOrientation();
        } else if (this._running) {
          let dt = frameDt;
          if (dt > 0.05) dt = 0.05;
          const nSub = Math.max(1, Math.min(8, Math.ceil(dt / STEP)));
          const h = dt / nSub;
          for (let i = 0; i < nSub; i++) {
            this._step(h);
            if (!this._running) break;
          }
          // Orientation only needs the FINAL pose — build it once per frame.
          this._recomputeOrientation();
          // Leaderboard stats + flight-plan recording.
          this.distance += (this.speed * frameDt) / 1000; // km
          const kmh = this.speed * 3.6;
          if (kmh > this.topSpeedKmh) this.topSpeedKmh = kmh;
          this._pathAcc += frameDt;
          if (this._pathAcc >= this._pathDt && this.path.length < 800) {
            this._pathAcc = 0;
            const c = window.Cesium.Cartographic.fromCartesian(this.position);
            this.path.push([
              +window.Cesium.Math.toDegrees(c.longitude).toFixed(6),
              +window.Cesium.Math.toDegrees(c.latitude).toFixed(6),
              +c.height.toFixed(1),
              +this.heading.toFixed(4),
            ]);
          }
        }

        this._stateAcc += frameDt;
        if (this._stateAcc >= 0.05) {
          this._stateAcc = 0;
          this._emitState(); // ~20 Hz HUD/audio update instead of every frame
        }

        this._logAcc += frameDt;
        if (this._logAcc >= 1) {
          this._logAcc = 0;
          log(
            `[${this.mode}] hdg ${Math.round(this.heading / D2R)}° pit ${Math.round(this.pitch / D2R)}° ` +
              `rol ${Math.round(this.roll / D2R)}° alt ${Math.round(this.alt)}m ` +
              `spd ${Math.round(this.speed * 3.6)} ` +
              (this.mode === "sim"
                ? `aoa ${Math.round(this._aoa / D2R)}° v/s ${this._vspeed >= 0 ? "+" : ""}${Math.round(this._vspeed)} flaps ${this.flaps}${this._stall ? " STALL" : ""}`
                : `agl ${this._groundValid ? Math.round(this.agl) + "m" : "—"}`)
          );
        }
      } catch (e) {
        if (!this._warned) {
          this._warned = true;
          console.warn("flight loop error (non-fatal):", e);
        }
      }
    };
    this.viewer.scene.preUpdate.addEventListener(this._preUpdate);
  }

  _stepArcade(h) {
    const C = window.Cesium;
    const P = this.P;
    const c = this.controls;
    this._t += h;

    const shp = (x) => Math.sign(x) * x * x; // input curve
    const inP = shp(clamp(c.pitch, -1, 1));
    const inR = shp(clamp(c.roll, -1, 1));
    const inRud = clamp(c.rudder, -1, 1);

    const minMs = P.minSpeedKmh / 3.6;
    const maxMs = P.maxSpeedKmh / 3.6;
    const auth = 0.6 + 0.4 * (minMs / Math.max(minMs, this.speed)); // calmer when fast

    // Throttle → target speed (eased, engine lag).
    this.throttle = clamp(this.throttle + c.throttle * 0.5 * h, 0, 1);
    const targetSpeed = minMs + (maxMs - minMs) * this.throttle;
    this.speed += (targetSpeed - this.speed) * (1 - Math.exp(-h / P.throttleLag));

    // Rotational inertia: input drives angular velocity; spring auto-level idle.
    const maxRoll = P.maxRollRateDeg * D2R * auth;
    const maxPitch = P.maxPitchRateDeg * D2R * auth;
    if (Math.abs(inR) > 0.01) {
      this._rollVel += (inR * maxRoll - this._rollVel) * (1 - Math.exp(-P.rotEase * h));
    } else {
      const w = P.autoFreq;
      this._rollVel += (-this.roll * w * w - 2 * P.autoDamp * w * this._rollVel) * h;
    }
    this.roll = clamp(this.roll + this._rollVel * h, -P.rollClampDeg * D2R, P.rollClampDeg * D2R);

    if (Math.abs(inP) > 0.01) {
      this._pitchVel += (inP * maxPitch - this._pitchVel) * (1 - Math.exp(-P.rotEase * h));
    } else {
      const w = P.autoFreq;
      this._pitchVel += (-this.pitch * w * w - 2 * P.autoDamp * w * this._pitchVel) * h;
    }
    this.pitch = clamp(this.pitch + this._pitchVel * h, -P.pitchClampDeg * D2R, P.pitchClampDeg * D2R);

    // Banked-turn coupling + rudder.
    const yawRate = Math.sin(this.roll) * P.turnFactor + inRud * P.rudderRateDeg * D2R;
    this.heading = wrap2pi(this.heading + yawRate * h);

    // Energy exchange + turn bleed.
    this.speed += -Math.sin(this.pitch) * 9.8 * P.energyFactor * h;
    this.speed -= Math.abs(yawRate) * this.speed * P.turnBleed * h;
    this.speed = clamp(this.speed, minMs * 0.5, maxMs * 1.1);

    // Move along a velocity vector that LAGS the nose (mass / drift feel).
    const b = this._basisFor(this.heading, this.pitch, this.roll);
    if (!this._velDir) this._velDir = C.Cartesian3.clone(b.F, new C.Cartesian3());
    const a = 1 - Math.exp(-h / P.velLag);
    this._velDir = norm(add(scale(this._velDir, 1 - a), scale(b.F, a)));
    addScaled(this.position, this._velDir, this.speed * h);

    this._vspeed = this.speed * Math.sin(this.pitch); // climb rate for the HUD
    if (this._altitude(h)) return;
    this.propAngle = wrap2pi(this.propAngle + (10 + this.throttle * 70) * h);
  }

  // Dispatch to the selected model.
  _step(h) {
    if (this.vehicleType === "balloon") this._stepBalloon(h);
    else if (this.mode === "sim") this._stepSim(h);
    else this._stepArcade(h);
  }

  // Simple, honest balloon: throttle is the burner (rise/descend, laggy), it
  // drifts gently with the "wind", A/D slowly steer the drift. Always upright.
  _stepBalloon(h) {
    const C = window.Cesium;
    const c = this.controls;
    this._t += h;
    const b = this._basisFor(this.heading, 0, 0);

    // Burner: Shift/Ctrl OR hold Space, with a slow (~4 s) heat lag — the lag is the game.
    const burner = c.throttle + (c.level ? 1 : 0);
    this.throttle = clamp(this.throttle + burner * 0.4 * h, 0, 1);
    const targetClimb = (this.throttle - 0.5) * 8; // ±4 m/s, neutral at 0.5
    this._vspeed += (targetClimb - this._vspeed) * (1 - Math.exp(-h / 4));

    // Steer by ALTITUDE: each wind layer blows a different way (real ballooning).
    const wind = balloonWind(this.agl);
    this.heading = wind.bearing; // face the drift
    const driftDir = norm(add(scale(b.n, Math.cos(wind.bearing)), scale(b.e, Math.sin(wind.bearing))));
    let vel = scale(b.u, this._vspeed);
    vel = add(vel, scale(driftDir, wind.speed));
    addScaled(this.position, vel, h);
    this.speed = C.Cartesian3.magnitude(vel);

    this.alt = C.Cartographic.fromCartesian(this.position).height;
    this._groundAcc += h;
    if (this._groundAcc >= 0.4) {
      this._groundAcc = 0;
      this._sampleGround();
    }
    this.agl = this._groundValid ? this._aglFilt : 9999;
    if (this._groundValid && this.agl < 4 && this._vspeed <= 0) {
      this._vspeed = 0;
      addScaled(this.position, b.u, 4 - this.agl); // rest ~4 m over ground, no crash
    }
    this.warning = "";
  }

  // Force-based light-sim model (Pillar 1): AoA-driven lift/drag, thrust,
  // gravity, stall, flaps. Velocity is a real 3D vector.
  _stepSim(h) {
    const C = window.Cesium;
    const P = this.P;
    const c = this.controls;
    this._t += h;

    const b = this._basisFor(this.heading, this.pitch, this.roll);
    const F = b.F, U = b.U, R = b.R, up = b.u;
    let v = this.velocity;
    let speed = C.Cartesian3.magnitude(v);
    const vhat = speed > 0.1 ? scale(v, 1 / speed) : C.Cartesian3.clone(F, new C.Cartesian3());

    // Air density falls off with altitude.
    const rho = 1.225 * Math.exp(-Math.max(0, this.alt) / 8500);
    const q = 0.5 * rho * speed * speed; // dynamic pressure

    // Angle of attack: nose vs velocity, in the plane's longitudinal plane.
    const vSide = dot(v, R);
    const vLong = sub(v, scale(R, vSide));
    const vLongHat = C.Cartesian3.magnitude(vLong) > 0.1 ? norm(vLong) : C.Cartesian3.clone(F, new C.Cartesian3());
    const alpha = Math.atan2(-dot(vLongHat, U), dot(vLongHat, F));
    this._aoa = alpha;

    // Lift coefficient with a real stall break + flap bonus.
    const a0 = -4 * D2R;
    const aCrit = 15 * D2R;
    const slope = P.clMax / (aCrit - a0);
    const flapCL = this.flaps === 40 ? 0.7 : this.flaps === 20 ? 0.35 : 0;
    let CL;
    if (Math.abs(alpha) <= aCrit + D2R) {
      CL = slope * (alpha - a0) + flapCL;
      this._stall = false;
    } else {
      const over = Math.abs(alpha) - aCrit;
      CL = Math.sign(alpha) * Math.max(0.55, P.clMax - over * 3.5) + flapCL * 0.5;
      this._stall = true;
    }
    CL = clamp(CL, -1.6, 2.4);

    // Forces. Lift ⊥ velocity, toward plane-up. Guard against the degenerate case
    // (velocity parallel to plane-up, near-vertical) that would yield NaN.
    let liftDir = sub(U, scale(vhat, dot(U, vhat)));
    liftDir = C.Cartesian3.magnitude(liftDir) < 1e-4 ? C.Cartesian3.clone(U, new C.Cartesian3()) : norm(liftDir);
    const L = q * P.wingArea * CL;
    const CD = P.cd0 + P.kInduced * CL * CL + (this.flaps / 40) * 0.045;
    const D = q * P.wingArea * CD;

    this.throttle = clamp(this.throttle + c.throttle * 0.5 * h, 0, 1);
    this._thrustN += (this.throttle * P.maxThrust - this._thrustN) * (1 - Math.exp(-h / 1.5));

    let force = scale(liftDir, L);
    force = add(force, scale(vhat, -D));
    force = add(force, scale(F, this._thrustN));
    force = add(force, scale(up, -9.81 * P.mass));

    // Bird flap: Space gives a rate-limited forward+up impulse (no engine).
    if (this.vehicleType === "bird" && P.flapForce > 0) {
      const nowMs = performance.now();
      if (this.controls.level && nowMs - this._lastFlap > 480) {
        this._lastFlap = nowMs;
        this._flapUntil = nowMs + 400; // ~one flap cycle
      }
      if (nowMs < this._flapUntil) {
        const flapDir = norm(add(scale(F, 0.55), scale(up, 0.83)));
        force = add(force, scale(flapDir, P.flapForce));
      }
    }

    const accel = scale(force, 1 / P.mass);
    this.velocity = add(v, scale(accel, h));
    addScaled(this.position, this.velocity, h);
    this.speed = C.Cartesian3.magnitude(this.velocity);
    this._vspeed = dot(this.velocity, up);

    // Rotation: control authority scales with dynamic pressure (mushy slow).
    const qRef = 0.5 * 1.225 * Math.pow(P.cruiseKmh / 3.6, 2);
    const auth = clamp(q / qRef, 0.12, 1.4);
    const shp = (x) => Math.sign(x) * x * x;
    const inP = shp(clamp(c.pitch, -1, 1));
    const inR = shp(clamp(c.roll, -1, 1));
    const inRud = clamp(c.rudder, -1, 1);

    this.pitch += inP * P.maxPitchRateDeg * D2R * auth * h;
    this.roll += inR * P.maxRollRateDeg * D2R * auth * h;
    this.heading = wrap2pi(
      this.heading + (Math.sin(this.roll) * P.turnFactor + inRud * P.rudderRateDeg * D2R) * h
    );

    // Natural stability (weathervane + trim + roll damping).
    if (speed > 3) {
      const velHeading = Math.atan2(dot(vhat, b.e), dot(vhat, b.n));
      const velPitch = Math.asin(clamp(dot(vhat, up), -1, 1));
      this.heading = wrap2pi(
        this.heading + shortAngle(this.heading, velHeading) * Math.min(1, P.weathervane * auth * h)
      );
      if (Math.abs(inP) < 0.01) {
        const trim = velPitch + P.trimAoADeg * D2R;
        this.pitch += (trim - this.pitch) * Math.min(1, P.pitchStab * auth * h);
      }
    }
    if (Math.abs(inR) < 0.01) this.roll += (0 - this.roll) * Math.min(1, P.rollDamp * h);

    // Stall buffet — a gentle, time-based shudder (not per-step random noise) so
    // it reads as buffet, not a seizure. Plus a slow wing-drop bias.
    if (this._stall) {
      this.pitch += Math.sin(this._t * 33) * 0.6 * D2R * h;
      this.roll += (Math.sin(this._t * 27) * 0.6 + 0.4) * D2R * h; // slight drop
    }

    this.pitch = clamp(this.pitch, -80 * D2R, 80 * D2R);
    this.roll = clamp(this.roll, -P.rollClampDeg * D2R, P.rollClampDeg * D2R);

    if (this._altitude(h)) return;
    if (this._stall) this.warning = "STALL";
    this.propAngle = wrap2pi(this.propAngle + (10 + this.throttle * 70) * h);
  }

  // Shared altitude sampling + floor/ceiling assist. Returns true if it crashed.
  _altitude(h) {
    const C = window.Cesium;
    this.alt = C.Cartographic.fromCartesian(this.position).height;
    this._groundAcc += h;
    if (this._groundAcc >= 0.4) {
      this._groundAcc = 0;
      this._sampleGround();
    }
    this.agl = this._groundValid ? this._aglFilt : 9999;

    const now = performance.now();
    const grace = now < this._graceUntil;
    if (this._groundValid && this.agl < FLOOR_WARN) {
      if (!this._lowSince) this._lowSince = now;
    } else {
      this._lowSince = 0;
    }
    // Latch the assist for ≥1.5 s once triggered so it can't flicker on/off
    // over rows of buildings (that flicker was the shudder).
    const sustained = this._lowSince && now - this._lowSince > 700;
    if (sustained && !grace) this._pullUntil = now + 1500;
    if (this._pullUntil && now < this._pullUntil && !grace) {
      this.warning = "PULL UP";
      this.pitch += (10 * D2R - this.pitch) * (1 - Math.exp(-1.2 * h)); // gentle
      this._pitchVel *= Math.exp(-3 * h);
      if (this._groundValid && this.agl < FLOOR_CRASH && this._lowSince && now - this._lowSince > 1100) {
        this._crash();
        return true;
      }
    } else if (this._groundValid && this.agl > CEILING_AGL) {
      this.warning = "THIN AIR";
    } else {
      this.warning = "";
    }
    return false;
  }

  // ---- geometry ----
  _basisFor(heading, pitch, roll) {
    const C = window.Cesium;
    const enu = C.Transforms.eastNorthUpToFixedFrame(this.position, C.Ellipsoid.WGS84, new C.Matrix4());
    const e = norm(col(enu, 0));
    const n = norm(col(enu, 1));
    const u = norm(col(enu, 2));
    const fh = add(scale(e, Math.sin(heading)), scale(n, Math.cos(heading)));
    const F = norm(add(scale(fh, Math.cos(pitch)), scale(u, Math.sin(pitch))));
    const upNoRoll = norm(add(scale(fh, -Math.sin(pitch)), scale(u, Math.cos(pitch))));
    const rightNoRoll = norm(cross(F, upNoRoll));
    const U = norm(add(scale(upNoRoll, Math.cos(roll)), scale(rightNoRoll, Math.sin(roll))));
    const R = norm(cross(F, U));
    return { e, n, u, fh, F, U, R };
  }

  // Orientation via Cesium's canonical HPR quaternion. The model-mount offsets
  // are pure additions in the SAME convention: modelYaw is a true yaw about up,
  // so correcting the mesh's facing never tilts it.
  _recomputeOrientation() {
    const C = window.Cesium;
    const P = this.P;
    const ambP = P.ambientDeg * D2R * Math.sin(this._t * 0.7);
    const ambR = P.ambientDeg * D2R * Math.sin(this._t * 0.53);
    const dynPitch = this.vehicleType === "balloon" ? 0 : this.pitch + ambP;
    const dynRoll = this.vehicleType === "balloon" ? 0 : this.roll + ambR;
    const hpr = new C.HeadingPitchRoll(
      this.heading + P.modelYawDeg * D2R,
      dynPitch + P.modelPitchDeg * D2R,
      dynRoll + P.modelRollDeg * D2R
    );
    this.orientation = C.Transforms.headingPitchRollQuaternion(
      this.position,
      hpr,
      C.Ellipsoid.WGS84,
      undefined,
      new C.Quaternion()
    );
  }

  // Precision-robust chase cam: lock the camera to the plane's LOCAL ENU frame
  // (Cesium then renders relative to the plane → no ECEF jitter) and look AT the
  // plane (keeps it centered, fixes the heli offset). Only the heading is
  // smoothed — a scalar, so no precision cost. Horizon stays level.
  _updateCamera(dt) {
    const C = window.Cesium;
    if (!this.position) return;
    const P = this.P;
    if (this._camHeading === undefined) this._camHeading = this.heading;
    const a = dt > 0 ? 1 - Math.exp(-dt / P.camTau) : 1;
    this._camHeading += shortAngle(this._camHeading, this.heading) * a;

    const enu = C.Transforms.eastNorthUpToFixedFrame(this.position, C.Ellipsoid.WGS84, new C.Matrix4());
    // Offset in ENU (east, north, up): behind the heading and above.
    const offset = new C.Cartesian3(
      -Math.sin(this._camHeading) * P.camBack,
      -Math.cos(this._camHeading) * P.camBack,
      P.camUp
    );
    this.viewer.camera.lookAtTransform(enu, offset);

    // Sense of speed: widen FOV gently as speed rises (heavily smoothed so it
    // can't shimmer). 60° cruise → ~76° at top speed.
    const minMs = P.minSpeedKmh / 3.6;
    const maxMs = P.maxSpeedKmh / 3.6;
    const sf = Math.max(0, Math.min(1, (this.speed - minMs) / Math.max(1, maxMs - minMs)));
    const targetFov = (60 + 16 * sf) * D2R;
    if (this._fov === undefined) this._fov = targetFov;
    this._fov += (targetFov - this._fov) * (dt > 0 ? 1 - Math.exp(-dt / 0.6) : 1);
    if (this.viewer.camera.frustum.fov !== undefined) this.viewer.camera.frustum.fov = this._fov;
  }

  _sampleGround() {
    const C = window.Cesium;
    let ok = false;
    try {
      if (this.viewer.scene.sampleHeightSupported) {
        const carto = C.Cartographic.fromCartesian(this.position);
        const h = this.viewer.scene.sampleHeight(carto, this.plane ? [this.plane] : undefined);
        if (h !== undefined && isFinite(h)) {
          // Median-filter the last 5 readings so a single rooftop hit can't
          // spike the AGL (that was the pull-up shudder over skyscrapers).
          this._aglBuf.push(this.alt - h);
          if (this._aglBuf.length > 5) this._aglBuf.shift();
          const s = this._aglBuf.slice().sort((a, b) => a - b);
          this._aglFilt = s[s.length >> 1];
          ok = true;
        }
      }
    } catch (e) {
      /* tiles streaming */
    }
    this._groundValid = ok;
  }

  _crash() {
    this.crashes++;
    log("crash → respawn");
    flash();
    this.pitch = 0;
    this.roll = 0;
    this._pitchVel = 0;
    this._rollVel = 0;
    this._velDir = null;
    this.speed = this.P.cruiseKmh / 3.6;
    this.throttle = 0.5;
    this.agl = 9999;
    this._groundValid = false;
    this._aglBuf = [];
    this._lowSince = 0;
    this._pullUntil = 0;
    this._graceUntil = performance.now() + 3000;
    this._setPositionLL(this.spawnLL.lat, this.spawnLL.lng, this.spawnGround + SPAWN_AGL);
    // Re-seed the sim velocity vector — otherwise it keeps the old downward
    // velocity and dives straight back into the ground (crash loop).
    this.velocity = scale(this._basisFor(this.heading, 0, 0).F, this.P.cruiseKmh / 3.6);
    this._thrustN = this.throttle * this.P.maxThrust;
    this._aoa = 0;
    this._vspeed = 0;
    this._stall = false;
    this._camHeading = this.heading;
    this._recomputeOrientation();
  }

  _setPositionLL(lat, lng, alt) {
    this.position = window.Cesium.Cartesian3.fromDegrees(lng, lat, alt);
  }

  _emitState() {
    this.onState({
      speedKmh: this.speed * 3.6,
      altM: this.alt,
      aglM: this.agl,
      headingDeg: (this.heading / D2R + 360) % 360,
      pitchDeg: this.pitch / D2R,
      rollDeg: this.roll / D2R,
      throttle: this.throttle,
      warning: this.warning,
      crashes: this.crashes,
      mode: this.mode,
      flaps: this.flaps,
      aoaDeg: this._aoa / D2R,
      vspeed: this._vspeed,
      stall: this._stall,
    });
  }

  async _waitForTiles(timeoutMs, onProgress) {
    const tileset = this.tileset;
    if (tileset.tilesLoaded) return;
    await new Promise((resolve) => {
      let done = false;
      const finish = () => {
        if (done) return;
        done = true;
        resolve();
      };
      const remove = tileset.initialTilesLoaded.addEventListener(() => {
        remove();
        finish();
      });
      const started = performance.now();
      const poll = () => {
        if (done) return;
        const frac = Math.min(0.95, (performance.now() - started) / timeoutMs);
        onProgress(0.4 + frac * 0.55, "Spooling up the tiles…");
        if (tileset.tilesLoaded || performance.now() - started > timeoutMs) return finish();
        requestAnimationFrame(poll);
      };
      requestAnimationFrame(poll);
    });
  }

  _teardown() {
    if (!this.viewer) return;
    if (this._preUpdate) {
      this.viewer.scene.preUpdate.removeEventListener(this._preUpdate);
      this._preUpdate = null;
    }
    if (this.plane) {
      this.viewer.entities.remove(this.plane);
      this.plane = null;
    }
    if (this._marker) {
      this.viewer.entities.remove(this._marker);
      this._marker = null;
    }
    // Release the locked camera frame so landing/next vehicle can reposition.
    this.viewer.camera.lookAtTransform(window.Cesium.Matrix4.IDENTITY);
    this._camHeading = undefined;
    this._recording = null;
    this._running = false;
    this._warned = false;
  }
}

// ---- helpers ----
function log(m) {
  if (window.__hbLog) window.__hbLog(m);
  else console.log("[HB]", m);
}
function logGPU() {
  try {
    const c = document.createElement("canvas");
    const gl = c.getContext("webgl2") || c.getContext("webgl");
    if (!gl) return;
    const ext = gl.getExtension("WEBGL_debug_renderer_info");
    const r = ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
    log("GPU: " + r);
  } catch (e) {
    /* ignore */
  }
}
function flash() {
  const el = document.getElementById("flash");
  if (!el) return;
  el.classList.add("show");
  setTimeout(() => el.classList.remove("show"), 500);
}
function col(m4, i) {
  const c = window.Cesium.Matrix4.getColumn(m4, i, new window.Cesium.Cartesian4());
  return new window.Cesium.Cartesian3(c.x, c.y, c.z);
}
function norm(v) {
  return window.Cesium.Cartesian3.normalize(v, v);
}
function add(a, b) {
  return window.Cesium.Cartesian3.add(a, b, new window.Cesium.Cartesian3());
}
function sub(a, b) {
  return window.Cesium.Cartesian3.subtract(a, b, new window.Cesium.Cartesian3());
}
function scale(a, s) {
  return window.Cesium.Cartesian3.multiplyByScalar(a, s, new window.Cesium.Cartesian3());
}
function cross(a, b) {
  return window.Cesium.Cartesian3.cross(a, b, new window.Cesium.Cartesian3());
}
function dot(a, b) {
  return window.Cesium.Cartesian3.dot(a, b);
}
function shortAngle(from, to) {
  let d = to - from;
  while (d > Math.PI) d -= 2 * Math.PI;
  while (d < -Math.PI) d += 2 * Math.PI;
  return d;
}
// Wind layers for the balloon — change altitude to catch a different direction.
function balloonWind(agl) {
  const D = Math.PI / 180;
  if (agl < 250) return { bearing: 60 * D, speed: 2.5 }; // low: toward ENE
  if (agl < 600) return { bearing: 200 * D, speed: 4.5 }; // mid: toward SSW
  return { bearing: 320 * D, speed: 6.5 }; // high: toward NW, faster
}
function addScaled(target, v, s) {
  return window.Cesium.Cartesian3.add(target, scale(v, s), target);
}
function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v));
}
function wrap2pi(a) {
  const t = Math.PI * 2;
  return ((a % t) + t) % t;
}
async function createGoogleTileset(C, key) {
  if (typeof C.createGooglePhotorealistic3DTileset !== "function") {
    throw new Error("This Cesium build lacks Google 3D Tiles support.");
  }
  // enableCollision off: camera is driven by lookAtTransform (no tile collision),
  // and ground sampling uses sampleHeight (pick path), so collision geometry is wasted.
  return await C.createGooglePhotorealistic3DTileset(key, { enableCollision: false });
}
