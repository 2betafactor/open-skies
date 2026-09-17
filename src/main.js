import { ensureEngine } from "./engine.js?v=single4";
import { VEHICLES } from "./vehicles.js?v=single4";
// main.js — app state machine (landing → loading → flying), Google Maps loader
// (Places), Cesium flight scene, presets.

import { Flight, DEFAULT_PARAMS } from "./flight.js?v=single4";
import { Controller } from "./controller.js?v=single4";
import { EngineAudio } from "./audio.js?v=single4";
import { HUD } from "./hud.js?v=single4";
import { buildTuner } from "./tuner.js?v=single4";

// ---- Diagnostic logger ----
function dlog(msg, isErr = false) {
  const el = document.getElementById("debug-log");
  if (el) {
    el.classList.add("show");
    const line = document.createElement("div");
    if (isErr) line.className = "err";
    line.textContent = msg;
    el.appendChild(line);
    el.scrollTop = el.scrollHeight;
  }
  (isErr ? console.error : console.log)("[HB]", msg);
}
window.__hbLog = dlog;
window.addEventListener("error", (e) => dlog("JS ERROR: " + (e.message || e.error), true));
window.addEventListener("unhandledrejection", (e) =>
  dlog("PROMISE REJECT: " + (e.reason && (e.reason.message || e.reason)), true)
);
dlog("boot: script loaded");

// ---- Preset flights (strong 3D-tile coverage) ----
// ---- Selectable vehicles (model + mount correction + physics params) ----

const PRESETS = [
  { emoji: "🏙️", name: "Manhattan", desc: "Skyscraper canyons", lat: 40.758, lng: -73.9855 },
  { emoji: "🗼", name: "Tokyo Bay", desc: "Odaiba & the bay", lat: 35.6329, lng: 139.8804 },
  { emoji: "🏔️", name: "Swiss Alps", desc: "Over Interlaken", lat: 46.6863, lng: 7.8632 },
  { emoji: "🏜️", name: "Grand Canyon", desc: "Down the gorge", lat: 36.0544, lng: -112.1401 },
  { emoji: "⛵", name: "Ithaka", desc: "Odysseus's Ionian isle", lat: 38.365, lng: 20.718 },
  { emoji: "🏞️", name: "Alyzia", desc: "Aitoloakarnanía coast", lat: 38.73, lng: 21.05 },
  { emoji: "🏔️", name: "Cape Town", desc: "Table Mountain & harbour", lat: -33.915, lng: 18.4233 },
  { emoji: "🏝️", name: "Key West", desc: "Island & turquoise sea", lat: 24.5551, lng: -81.78 },
];

const app = {
  audio: new EngineAudio(),
  hud: null,
  flight: null,
  controller: null,
  sceneReady: null,
  autocomplete: null,
  cancelled: false,
  flying: false,
  vehicle: VEHICLES[0],
  quality: "balanced", // default
  destination: PRESETS[0],
};

const QUALITY = [
  { id: "performance", label: "Performance" },
  { id: "balanced", label: "Balanced" },
  { id: "quality", label: "High detail" },
];

// ================= Google Maps loader =================
let mapsPromise;
function loadMaps() {
  if (mapsPromise) return mapsPromise;
  const key = window.HORSEBACK_CONFIG?.GOOGLE_MAPS_API_KEY;
  if (!key || key === "YOUR_API_KEY_HERE") return Promise.reject(new Error("Real-world scenery is not configured yet. Sandbox is ready to fly."));
  mapsPromise = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Location search timed out. Try Sandbox or retry.")), 15000);
    window.initMaps = () => { clearTimeout(timer); if (!app.autocomplete) setupSearch(); resolve(); };
    const script = document.createElement("script");
    script.src = "https://maps.googleapis.com/maps/api/js?key=" + encodeURIComponent(key) + "&libraries=places&callback=initMaps&loading=async";
    script.onerror = () => { clearTimeout(timer); reject(new Error("Location search is unavailable. Choose a featured destination or try Sandbox.")); };
    document.head.appendChild(script);
  }).catch(e => { mapsPromise = null; throw e; });
  return mapsPromise;
}
async function selectWorld(world) {
  app.world = world;
  document.querySelectorAll("[data-world]").forEach(b => b.setAttribute("aria-pressed", String(b.dataset.world === world)));
  document.getElementById("sandbox-panel").hidden = world !== "sandbox";
  document.getElementById("maps-panel").hidden = world !== "google";
  document.getElementById("launch-panel").hidden = world !== "google";
  setLandingStatus("");
  if (world === "google") {
    try { await loadMaps(); } catch (e) { if (app.world === "google") setLandingStatus(e.message, true); }
  }
}

// ================= Init =================
function initApp() {
  dlog("initializing independent flight modes");
  app.world = "google";
  document.querySelectorAll("[data-world]").forEach(b => b.addEventListener("click", () => selectWorld(b.dataset.world)));
  document.getElementById("btn-sandbox").addEventListener("click", () => takeOff(0, 0, "Meadow Airfield"));
  document.getElementById("place-input").addEventListener("input", e => {
    const pending = !!e.target.value.trim();
    document.getElementById("btn-takeoff").disabled = pending;
    setLandingStatus(pending ? "Choose a search suggestion, or select a destination below." : "");
  });
  document.getElementById("btn-takeoff").addEventListener("click", () => {
    const p = app.destination;
    takeOff(p.lat, p.lng, p.name);
  });
  document.getElementById("btn-help").addEventListener("click", () => {
    const help = document.getElementById("controls-help"); help.open = !help.open;
    if (help.open) help.scrollIntoView({ behavior: "smooth", block: "nearest" });
  });
  renderQuality();
  renderPresets();

  setupGeolocation();
  setupResult();
  setupTouch();
  speedFx.init();
  renderBoard("landing-board");
  document.getElementById("btn-share").addEventListener("click", shareFlight);
  document.getElementById("btn-record").addEventListener("click", recordAndShare);
  document.getElementById("btn-fly-now").addEventListener("click", dismount); // leave replay → landing
  document.getElementById("btn-loading-cancel").addEventListener("click", cancelLoading);

  app.flight = new Flight("cesiumContainer");
  app.flight.onError = (e) => {
    const msg = (e && (e.message || e.toString())) || "unknown";
    showError("The scenery could not be rendered. Try Performance graphics and reload.");
  };
  app.sceneReady = Promise.resolve();

  app.hud = new HUD({
    onMute: () => app.hud.setMuted(app.audio.toggleMute()),
    onDismount: dismount,
  });
  app.hud.bind();

  app.controller = new Controller(app.flight.controls, {
    onDismount: dismount,
    onFlaps: () => app.flight.cycleFlaps(),
    onToggleMode: () => app.flight.toggleMode(),
    onCamera: changeCamera,
  });

  document.getElementById("btn-camera").addEventListener("click", changeCamera);

  app.tuner = buildTuner(app.flight.P);
  app.tuner.setDefaults(DEFAULT_PARAMS);
  const tuneBtn = document.getElementById("btn-tune");
  if (tuneBtn) tuneBtn.addEventListener("click", () => app.tuner.toggle());

  // Shared flight link → jump straight into the replay.
  const sharedId = new URLSearchParams(location.search).get("flight");
  if (sharedId) app.sceneReady.then(() => watchFlight(sharedId)).catch(() => showScreen("landing"));
  else {
    showScreen("landing");
    selectWorld("google");
  }
}

// ================= Landing =================
function renderQuality() {
  const wrap = document.getElementById("quality");
  if (!wrap) return;
  wrap.innerHTML = '<span class="quality-cap">Graphics</span>';
  for (const q of QUALITY) {
    const btn = document.createElement("button");
    btn.setAttribute("aria-pressed", String(q.id === app.quality));
    btn.className = "quality-btn" + (q.id === app.quality ? " active" : "");
    btn.textContent = q.label;
    btn.addEventListener("click", () => {
      app.quality = q.id;
      if (app.flight) app.flight.setQuality(q.id);
      for (const b of wrap.querySelectorAll(".quality-btn")) { b.classList.remove("active"); b.setAttribute("aria-pressed", "false"); }
      btn.setAttribute("aria-pressed", "true");
      btn.classList.add("active");
    });
    wrap.appendChild(btn);
  }
}

function renderPresets() {
  const wrap = document.getElementById("presets");
  wrap.innerHTML = "";
  for (const p of PRESETS) {
    const card = document.createElement("button");
    card.className = "preset-card";
    card.innerHTML = `
      <span class="preset-emoji">${p.emoji}</span>
      <span class="preset-name">${p.name}</span>
      <span class="preset-desc">${p.desc}</span>`;
    card.setAttribute("aria-pressed", String(p.name === app.destination.name));
    card.addEventListener("click", () => selectDestination(p));
    wrap.appendChild(card);
  }
}

function setupSearch() {
  const input = document.getElementById("place-input");
  app.autocomplete = new google.maps.places.Autocomplete(input, { fields: ["geometry", "name"] });
  app.autocomplete.addListener("place_changed", () => {
    const place = app.autocomplete.getPlace();
    if (!place.geometry || !place.geometry.location) {
      setLandingStatus("Pick a place from the dropdown to fly there.", true);
      return;
    }
    const loc = place.geometry.location;
    selectDestination({ lat: loc.lat(), lng: loc.lng(), name: place.name || "Your destination" });
  });
}

// ---- Speed FX: radial motion streaks + tunnel vignette that ramp up with
// airspeed. Purely ambient (no UI), invisible while cruising, dramatic when fast.
const speedFx = (() => {
  let canvas, ctx, W = 0, H = 0, dpr = 1;
  let streaks = [];
  let intensity = 0, target = 0, raf = 0;
  const rand = Math.random;

  function resize() {
    if (!canvas) return;
    dpr = Math.min(2, window.devicePixelRatio || 1);
    W = canvas.width = Math.max(1, Math.round(canvas.clientWidth * dpr));
    H = canvas.height = Math.max(1, Math.round(canvas.clientHeight * dpr));
  }
  function init() {
    canvas = document.getElementById("speedfx");
    if (!canvas) return;
    ctx = canvas.getContext("2d");
    for (let i = 0; i < 70; i++) {
      streaks.push({ a: rand() * Math.PI * 2, r: 0.15 + rand(), sp: 0.003 + rand() * 0.01, len: 0.05 + rand() * 0.1 });
    }
    resize();
    window.addEventListener("resize", resize);
  }
  function setSpeedFrac(f) {
    target = Math.max(0, Math.min(1, f || 0));
    if (!raf && (target > 0.003 || intensity > 0.003)) loop();
  }
  function loop() {
    raf = requestAnimationFrame(loop);
    intensity += (target - intensity) * 0.07;
    draw();
    if (intensity < 0.004 && target < 0.004) {
      cancelAnimationFrame(raf);
      raf = 0;
      if (ctx) ctx.clearRect(0, 0, W, H);
    }
  }
  function draw() {
    if (!ctx) return;
    ctx.clearRect(0, 0, W, H);
    const cx = W / 2, cy = H / 2;
    const maxR = Math.hypot(cx, cy);
    // tunnel vignette
    const vg = ctx.createRadialGradient(cx, cy, maxR * 0.32, cx, cy, maxR);
    vg.addColorStop(0, "rgba(0,0,0,0)");
    vg.addColorStop(1, `rgba(6,10,20,${0.32 * intensity})`);
    ctx.fillStyle = vg;
    ctx.fillRect(0, 0, W, H);
    // streaks flying outward from the centre
    ctx.lineCap = "round";
    for (const s of streaks) {
      s.r += s.sp * (0.4 + intensity * 2.0);
      if (s.r > 1.25) { s.r = 0.12; s.a = rand() * Math.PI * 2; }
      const r0 = s.r * maxR;
      const r1 = (s.r + s.len * (0.6 + intensity)) * maxR;
      const ca = Math.cos(s.a), sa = Math.sin(s.a);
      const fade = Math.min(1, (s.r - 0.12) * 2.2); // fade in near centre
      ctx.strokeStyle = `rgba(255,255,255,${0.11 * intensity * fade})`;
      ctx.lineWidth = (0.8 + s.r * 1.6) * dpr;
      ctx.beginPath();
      ctx.moveTo(cx + ca * r0, cy + sa * r0);
      ctx.lineTo(cx + ca * r1, cy + sa * r1);
      ctx.stroke();
    }
  }
  return { init, resize, setSpeedFrac };
})();

// ---- Touch controls (mobile / tablet) ----
function setupTouch() {
  if (matchMedia("(pointer: coarse)").matches || "ontouchstart" in window || navigator.maxTouchPoints > 0) {
    document.body.classList.add("touch");
  }
  const clamp1 = (x) => (Number.isFinite(x) ? Math.max(-1, Math.min(1, x)) : 0);
  const joy = document.getElementById("joy");
  const knob = document.getElementById("joy-knob");
  let active = false;
  let cx = 0;
  let cy = 0;
  let R = 60;
  let steeringPointer = null;
  const steer = (roll, pitch) => {
    if (app.flight) {
      app.flight.controls.roll = roll; // direct, responsive (clamp1 keeps it finite)
      app.flight.controls.pitch = pitch;
    }
  };
  const start = (e) => {
    if (active) return;
    steeringPointer = e.pointerId;
    joy.setPointerCapture(e.pointerId);
    active = true;
    const r = joy.getBoundingClientRect();
    cx = r.left + r.width / 2;
    cy = r.top + r.height / 2;
    R = r.width / 2 - 8;
    move(e);
  };
  const move = (e) => {
    if (!active || e.pointerId !== steeringPointer) return;
    let dx = e.clientX - cx;
    let dy = e.clientY - cy;
    const d = Math.hypot(dx, dy) || 1;
    if (d > R) {
      dx = (dx / d) * R;
      dy = (dy / d) * R;
    }
    knob.style.transform = `translate(${dx.toFixed(1)}px, ${dy.toFixed(1)}px)`;
    steer(clamp1(dx / R), clamp1(-dy / R)); // push up = pitch up
  };
  const end = (e) => {
    if (!active || (e?.pointerId != null && e.pointerId !== steeringPointer)) return;
    steeringPointer = null;
    active = false;
    knob.style.transform = "translate(0,0)";
    steer(0, 0);
  };
  window.addEventListener("blur", () => end());
  joy.addEventListener("pointerdown", start);
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", end);
  window.addEventListener("pointercancel", end);

  // --- Throttle lever: drag up/down to SET the throttle, like a real quadrant.
  // Sets flight.throttle directly (absolute) and zeroes the rate control so the
  // physics leaves it exactly where you put it. It stays put when you let go.
  const lever = document.getElementById("throttle-lever");
  const tlFill = document.getElementById("tl-fill");
  const tlKnob = document.getElementById("tl-knob");
  if (lever && tlFill && tlKnob) {
    const PAD = 12; // knob bottom inset (matches CSS)
    const KNOB = 40; // grip height (matches CSS)
    const SLOT = 32; // total slot inset top+bottom (matches CSS)
    let dragging = false;
    const applyFrac = (frac) => {
      if (!Number.isFinite(frac)) frac = 0.5; // never set a NaN throttle
      frac = Math.max(0, Math.min(1, frac));
      if (app.flight) {
        app.flight.throttle = frac;
        app.flight.controls.throttle = 0; // absolute — don't let the rate control fight it
      }
      const H = lever.getBoundingClientRect().height;
      tlFill.style.height = Math.max(4, frac * (H - SLOT)).toFixed(1) + "px"; // thrust rises in the slot
      const travel = Math.max(0, H - PAD * 2 - KNOB);
      tlKnob.style.transform = `translateY(${(-frac * travel).toFixed(1)}px)`;
    };
    const fracFromEvent = (e) => {
      const r = lever.getBoundingClientRect();
      const travel = r.height - PAD * 2 - KNOB;
      if (travel <= 0) return 0.5; // lever not laid out yet — avoid divide-by-zero
      const y = e.clientY - (r.top + PAD + KNOB / 2);
      return 1 - y / travel;
    };
    lever.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      dragging = true;
      try { lever.setPointerCapture(e.pointerId); } catch (err) {}
      applyFrac(fracFromEvent(e));
    });
    lever.addEventListener("pointermove", (e) => {
      if (dragging) applyFrac(fracFromEvent(e));
    });
    const stop = () => { dragging = false; };
    lever.addEventListener("pointerup", stop);
    lever.addEventListener("pointercancel", stop);
    // Expose so a new flight can reset the lever to its starting throttle (0.5).
    app._syncThrottleLever = () => applyFrac(app.flight ? app.flight.throttle : 0.5);
  }
}

// ---- Tilt-to-steer (device gyroscope) ----
function setupTilt() {
  const btn = document.getElementById("btn-tilt");
  if (!btn) return;
  let enabled = false;
  let neutral = null;
  let sRoll = 0, sPitch = 0; // low-passed control values (steady, plane-like)
  const clamp1 = (x) => Math.max(-1, Math.min(1, x));
  const deadzone = (x) => (Math.abs(x) < 0.05 ? 0 : x); // ignore tiny hand-shake

  const handler = (e) => {
    if (e.beta == null || e.gamma == null || !app.flight) return;
    if (!neutral) {
      neutral = { beta: e.beta, gamma: e.gamma }; // calibrate to how you're holding it
      return;
    }
    const angle = (screen.orientation && screen.orientation.angle) || window.orientation || 0;
    const db = e.beta - neutral.beta;
    const dg = e.gamma - neutral.gamma;
    let roll, pitch;
    if (angle === 90) {
      roll = db; pitch = -dg;
    } else if (angle === 270 || angle === -90) {
      roll = -db; pitch = dg;
    } else {
      roll = dg; pitch = -db; // portrait
    }
    const S = 1 / 32; // ~32° tilt = full deflection (gentler than before)
    const tr = deadzone(clamp1(roll * S));
    const tp = deadzone(clamp1(pitch * S));
    // Ease toward the target so the plane banks smoothly instead of snapping —
    // this is what makes tilt-flying feel like a real aircraft, not a spirit level.
    sRoll += (tr - sRoll) * 0.25;
    sPitch += (tp - sPitch) * 0.25;
    app.flight.controls.roll = sRoll;
    app.flight.controls.pitch = sPitch;
  };

  const setLabel = () => {
    btn.textContent = enabled ? "🎮 Tilt: ON" : "🎮 Tilt: OFF";
    btn.classList.toggle("on", enabled);
  };
  const enable = () => {
    neutral = null;
    sRoll = 0; sPitch = 0;
    window.addEventListener("deviceorientation", handler);
    enabled = true;
    document.body.classList.add("tilt-on"); // CSS hides the stick
    setLabel();
  };
  const disable = () => {
    window.removeEventListener("deviceorientation", handler);
    enabled = false;
    document.body.classList.remove("tilt-on");
    if (app.flight) {
      app.flight.controls.roll = 0;
      app.flight.controls.pitch = 0;
    }
    setLabel();
  };

  btn.addEventListener("click", async () => {
    if (enabled) return disable();
    const DOE = window.DeviceOrientationEvent;
    if (DOE && typeof DOE.requestPermission === "function") {
      try {
        const res = await DOE.requestPermission(); // iOS 13+ needs this from a tap
        if (res !== "granted") {
          alert("Motion access was denied. Enable it in Settings → Safari → Motion & Orientation Access.");
          return;
        }
      } catch (e) {
        return;
      }
    }
    enable();
  });
  setLabel();
}

function setupGeolocation() {
  document.getElementById("btn-geo").addEventListener("click", () => {
    if (!navigator.geolocation) {
      setLandingStatus("Geolocation isn't available in this browser.", true);
      return;
    }
    setLandingStatus("Finding you…");
    navigator.geolocation.getCurrentPosition(
      (pos) => { if (app.world === "google") selectDestination({lat: pos.coords.latitude, lng: pos.coords.longitude, name: "Your location"}); },
      () => setLandingStatus("Couldn't get your location. Try searching instead.", true),
      { enableHighAccuracy: true, timeout: 10000 }
    );
  });
}

function setLandingStatus(msg, isError = false) {
  const el = document.getElementById("landing-status");
  el.textContent = msg;
  el.classList.toggle("error", isError);
}

// ================= Take off =================
async function takeOff(lat, lng, label, opts = {}) {
  if (app.loading) return;
  app.loading = true;
  app.cancelled = false;
  app.flying = false;
  if (app.flight) app.flight.locationLabel = label; // used to caption shared screenshots
  // Unlock/resume audio NOW, inside the click gesture — before the tile-load
  // await — or Safari leaves the context suspended and there's no engine sound.
  app.audio.start();

  showScreen("ride");
  if (app.flight.viewer) app.flight.viewer.resize();
  showLoading(true, `Prepping flight over ${label}…`);

  try {
    setLoading(.08, "Preparing the 3D engine…");
    await ensureEngine();
    if (app.cancelled) return;
    await app.flight.init(window.HORSEBACK_CONFIG?.GOOGLE_MAPS_API_KEY, app.world);
    if (app.cancelled) return;

    app.flight.setQuality(app.quality);
    app.flight.setVehicle(app.vehicle);
    await app.flight.spawn(lat, lng, (frac, lbl) => {
      if (!app.cancelled) setLoading(frac, lbl);
    }, opts);
    if (app.cancelled) return;

    showLoading(false);
    beginFlight();
  } catch (err) {
    console.error(err);
    if (app.cancelled) return;
    showLoading(false);
    showScreen("landing");
    app.audio.suspend();
    app.flight.dispose();
    setLandingStatus("Couldn’t load scenery at that destination. Try another place or Sandbox.", true);
  } finally {
    app.loading = false;
    if (app.cancelled) app.flight.dispose();
  }
}

function beginFlight() {
  Object.assign(app.flight.controls, { pitch: 0, roll: 0, rudder: 0, throttle: 0, level: false });
  app.audio.start();
  app.hud.setMuted(app.audio.muted);
  app.controller.bind();
  requestWakeLock(); // stop phones/tablets from sleeping mid-flight
  if (app._syncThrottleLever) app._syncThrottleLever(); // lever starts at cruise (0.5)
  speedFx.resize(); // canvas now has real dimensions (ride screen is visible)

  const maxKmh = (app.flight.P && app.flight.P.maxSpeedKmh) || 520;
  let lastWarn = "";
  let lastCrashes = app.flight.crashes || 0;
  app.flight.onState = (s) => {
    app.hud.update(s);
    document.getElementById("course-status").textContent = app.vehicle.name + " · " + (app.world === "sandbox" ? app.flight.sandbox.status(app.flight.position) : "Free flight");
    app.audio.setThrottle(s.throttle);
    app.audio.setSpeed(Math.max(0, Math.min(1, (s.speedKmh / 3.6 - 11) / (97 - 11))));
    // Speed streaks ramp in above ~60% of top speed, max out near the redline.
    speedFx.setSpeedFrac((s.speedKmh / maxKmh - 0.58) / 0.42);
    // Haptics — a real cockpit shakes. Buzz on a fresh warning, harder on impact.
    if (navigator.vibrate) {
      if ((s.crashes || 0) > lastCrashes) navigator.vibrate([90, 40, 90]);
      else if (s.warning && s.warning !== lastWarn) navigator.vibrate(50);
    }
    lastWarn = s.warning || "";
    lastCrashes = s.crashes || 0;
  };

  app.flying = true;
  app.flight.start();
}

// Keep the display awake while flying (mobile screens sleep after ~30 s idle).
let _wakeLock = null;
async function requestWakeLock() {
  try {
    if ("wakeLock" in navigator) {
      const lock = await navigator.wakeLock.request("screen");
      if (!app.flying) { await lock.release(); return; }
      _wakeLock = lock;
      lock.addEventListener("release", () => { if (_wakeLock === lock) _wakeLock = null; });
    }
  } catch (e) {
    /* not supported / denied — harmless */
  }
}
function releaseWakeLock() {
  try {
    if (_wakeLock) { _wakeLock.release(); _wakeLock = null; }
  } catch (e) {}
}
document.addEventListener("visibilitychange", () => {
  // Wake locks drop when you switch tabs — re-acquire on return if still flying.
  if (document.visibilityState === "visible" && app.flying && !_wakeLock) requestWakeLock();
});

function dismount() {
  const wasFlying = app.flying;
  const flight = app.flight ? app.flight.getFlight() : null;
  app.flying = false;
  releaseWakeLock();
  speedFx.setSpeedFrac(0); // fade out the streaks
  if (app.controller) app.controller.unbind();
  if (app.flight) app.flight.dispose();
  if (app.audio) app.audio.suspend();
  setLandingStatus("");
  if (wasFlying && flight && flight.distanceKm > 0.05) {
    showResult(flight);
  } else {
    goLanding();
  }
}

// ================= Results + leaderboard =================
function showResult(flight) {
  app.lastFlight = flight;
  document.getElementById("result-distance").textContent = flight.distanceKm.toFixed(2) + " km";
  document.getElementById("result-time").textContent = formatTime(flight.timeSec);
  document.getElementById("result-topspeed").textContent = Math.round(flight.topSpeedKmh) + " km/h";
  document.getElementById("result-submit-row").style.display = "";
  document.getElementById("result-share").style.display = "none";
  document.getElementById("btn-submit-score").disabled = false;
  showScreen("result");
  renderBoard("result-board");
}

function setupResult() {
  document.getElementById("btn-submit-score").addEventListener("click", async () => {
    const btn = document.getElementById("btn-submit-score");
    const name = (document.getElementById("score-name").value || "PILOT").trim();
    btn.disabled = true;
    try {
      const res = await fetch("/api/scores", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, ...app.lastFlight }),
      });
      if (!res.ok) throw new Error("Score submission failed");
      const data = await res.json(); // { id, board }
      renderBoardData("result-board", data.board, name.toUpperCase());
      document.getElementById("result-submit-row").style.display = "none";
      showShare(data.id);
    } catch (e) {
      btn.disabled = false;
      toast("Couldn’t submit your score. Please retry.");
    }
  });
  document.getElementById("btn-result-again").addEventListener("click", goLanding);
  // Just three: Instagram, TikTok, Facebook.
  document.querySelectorAll("#share-socials [data-share]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const link = document.getElementById("share-link").value;
      const text = "Watch my Open Skies flight ✈️ #OpenSkies";
      if (btn.dataset.share === "fb") {
        // Facebook accepts a link on the web — open its sharer directly.
        window.open(
          "https://www.facebook.com/sharer/sharer.php?u=" + encodeURIComponent(link),
          "_blank",
          "noopener,noreferrer"
        );
      } else {
        // Instagram & TikTok have no web share — the native sheet is the only way
        // (and the 🎬 clip is the best thing to post there).
        shareLink(link, text);
      }
    });
  });
}

// Open the OS share sheet (Instagram, TikTok, WhatsApp, Messages…) for a link.
async function shareLink(url, text) {
  try {
    if (navigator.share) {
      await navigator.share({ title: "Open Skies", text, url });
    } else if (navigator.clipboard) {
      await navigator.clipboard.writeText(url);
      toast("Link copied — paste it into Instagram or TikTok!");
    }
  } catch (e) {
    /* user dismissed the share sheet — ignore */
  }
}

// Share the CURRENT view as an image (works any time during a flight).
async function shareFlight() {
  if (!app.flight) return;
  const btn = document.getElementById("btn-share");
  if (btn) btn.disabled = true;
  try {
    const blob = await app.flight.capture();
    const label = (app.flight && app.flight.locationLabel) || "the world";
    const url = location.origin + location.pathname;
    const text = `Flying over ${label} on Open Skies ✈️  #OpenSkies`;
    const file = blob && new File([blob], "open-skies.png", { type: "image/png" });
    if (file && navigator.canShare && navigator.canShare({ files: [file] })) {
      await navigator.share({ files: [file], title: "Open Skies", text });
    } else if (navigator.share) {
      await navigator.share({ title: "Open Skies", text, url });
    } else if (blob) {
      // Desktop: no share sheet — save the image and copy the link so they can post it.
      downloadBlob(blob, "open-skies.png");
      if (navigator.clipboard) await navigator.clipboard.writeText(url);
      toast("Photo saved & link copied — post it to Instagram / TikTok!");
    }
  } catch (e) {
    /* cancelled or capture failed — ignore */
  } finally {
    if (btn) btn.disabled = false;
  }
}

function downloadBlob(blob, name) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}

// Small transient message overlay.
let _toastTimer = null;
function toast(msg) {
  let el = document.getElementById("toast");
  if (!el) {
    el = document.createElement("div");
    el.id = "toast";
    el.className = "toast";
    document.body.appendChild(el);
  }
  el.textContent = msg;
  el.classList.add("show");
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(() => el.classList.remove("show"), 3200);
}

// Record a 10-second video clip of the live flight, then open the share sheet.
let _clipRecording = false;
async function recordAndShare() {
  if (!app.flight || _clipRecording) return;
  _clipRecording = true;
  const btn = document.getElementById("btn-record");
  if (btn) btn.disabled = true;
  showRec(true, 10);
  try {
    const blob = await app.flight.recordClip(10, (left) => showRec(true, left));
    showRec(false);
    if (!blob) {
      toast("Video recording isn't supported on this browser — try the 📤 photo share.");
      return;
    }
    const ext = blob.type.indexOf("mp4") >= 0 ? "mp4" : "webm";
    const file = new File([blob], "open-skies-flight." + ext, { type: blob.type });
    const text = "My Open Skies flight ✈️  #OpenSkies";
    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      await navigator.share({ files: [file], title: "Open Skies", text });
    } else {
      downloadBlob(blob, "open-skies-flight." + ext);
      toast("Clip saved — post it to Instagram, TikTok or Facebook!");
    }
  } catch (e) {
    showRec(false);
    toast("Couldn't record the clip.");
  } finally {
    _clipRecording = false;
    if (btn) btn.disabled = false;
  }
}

function showRec(on, n) {
  let el = document.getElementById("rec-indicator");
  if (!el) {
    el = document.createElement("div");
    el.id = "rec-indicator";
    el.className = "rec-indicator";
    el.innerHTML = '<span class="rec-dot"></span> REC <b id="rec-count"></b>s';
    document.body.appendChild(el);
  }
  if (typeof n === "number") {
    const c = el.querySelector("#rec-count");
    if (c) c.textContent = n;
  }
  el.classList.toggle("show", !!on);
}

function showShare(id) {
  if (!id) return;
  const link = location.origin + location.pathname + "?flight=" + id;
  document.getElementById("share-link").value = link;
  document.getElementById("result-share").style.display = "";
}

// ---- Watch a saved flight (replay) ----
async function watchFlight(id) {
  if (app.loading) return;
  app.loading = true;
  app.cancelled = false;
  app.flying = false;
  document.body.classList.add("replaying"); // hides controls, shows REPLAY + Fly now
  showScreen("ride");
  if (app.flight.viewer) app.flight.viewer.resize();
  showLoading(true, "Loading flight…");
  try {
    await app.sceneReady;
    const r = await fetch("/api/flight?id=" + encodeURIComponent(id));
    const flight = await r.json();
    if (!flight || !flight.path || !flight.path.length) throw new Error("not found");
    if (app.cancelled) return;
    await ensureEngine();
    if (app.cancelled) return;
    await app.flight.init(window.HORSEBACK_CONFIG?.GOOGLE_MAPS_API_KEY, flight.world || "google");
    document.getElementById("course-status").textContent = (flight.world === "sandbox" ? "Sandbox" : "Real world") + " · replay";
    if (app.cancelled) return;
    app.flight.onState = s => app.hud.update(s);
    app.flight.onReplayEnd = () => {
      app.flight.dispose();
      goLanding();
    };
    await app.flight.startReplay(flight.path, (f, l) => setLoading(f, l), flight.vehicle || "plane");
    if (app.cancelled) return;
    showLoading(false);
  } catch (e) {
    console.error(e);
    showLoading(false);
    goLanding();
    setLandingStatus("Couldn’t load that flight. Please retry or start a new flight.", true);
  } finally {
    app.loading = false;
    if (app.cancelled) app.flight.dispose();
  }
}

function goLanding() {
  document.body.classList.remove("replaying");
  showScreen("landing");
  renderBoard("landing-board");
}

async function renderBoard(elId, highlight) {
  try {
    const r = await fetch("/api/scores");
    renderBoardData(elId, await r.json(), highlight);
  } catch (e) {
    renderBoardData(elId, [], highlight);
  }
}

function renderBoardData(elId, data, highlight) {
  const el = document.getElementById(elId);
  if (!el) return;
  if (!data || !data.length) {
    el.innerHTML = '<div class="board-empty">No flights yet — be the first! ✈️</div>';
    return;
  }
  const medal = ["🥇", "🥈", "🥉"];
  el.innerHTML = data
    .slice(0, 10)
    .map(
      (s, i) => `<div class="board-row${s.name === highlight ? " me" : ""}">
        <span class="board-rank">${medal[i] || i + 1}</span>
        <span class="board-name">${escapeHtml(s.name)}</span>
        <span class="board-dist">${(s.distanceKm || 0).toFixed(1)} km</span>
        ${s.id ? `<button class="board-watch" data-id="${escapeHtml(s.id)}" title="Watch this flight">▶</button>` : ""}
      </div>`
    )
    .join("");
  for (const btn of el.querySelectorAll(".board-watch")) {
    btn.addEventListener("click", () => watchFlight(btn.dataset.id));
  }
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
function formatTime(sec) {
  sec = Math.max(0, Math.floor(sec));
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return m + ":" + String(s).padStart(2, "0");
}

function cancelLoading() {
  app.cancelled = true;
  app.audio.suspend();
  document.body.classList.remove("replaying");
  if (app.controller) app.controller.unbind();
  if (app.flight) app.flight.dispose(); // tear down the loop/entity if spawn already ran
  showScreen("landing");
  setLandingStatus("Flight cancelled.");
}

// ================= Screen helpers =================
function showScreen(name) {
  for (const el of document.querySelectorAll(".screen")) el.classList.remove("active");
  const target = document.getElementById("screen-" + name);
  if (target) target.classList.add("active");
}

function showLoading(on, text) {
  document.getElementById("screen-loading").classList.toggle("active", on);
  if (on) setLoading(0, text || "Loading…");
}

function setLoading(frac, label) {
  document.getElementById("loading-bar").style.width = Math.round(frac * 100) + "%";
  if (label) document.getElementById("loading-sub").textContent = label;
}

function showError(msg) {
  const el = document.getElementById("error-banner");
  el.textContent = msg;
  el.classList.add("show");
}

initApp();

function selectDestination(destination) {
  app.destination = destination;
  document.getElementById("place-input").value = "";
  document.getElementById("btn-takeoff").disabled = false;
  document.getElementById("selected-route").textContent = destination.name;
  for (const card of document.querySelectorAll(".preset-card")) {
    card.setAttribute("aria-pressed", String(card.querySelector(".preset-name").textContent === destination.name));
  }
  setLandingStatus("");
}
function changeCamera() {
  app.flight.toggleCamera();
  document.getElementById("btn-camera").textContent = app.flight.cameraView === "profile" ? "Profile" : "Chase";
}
