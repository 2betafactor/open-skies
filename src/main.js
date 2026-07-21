// main.js — app state machine (landing → loading → flying), Google Maps loader
// (Places), Cesium flight scene, presets.

import { Flight, DEFAULT_PARAMS } from "./flight.js";
import { Controller } from "./controller.js";
import { EngineAudio } from "./audio.js";
import { HUD } from "./hud.js";
import { buildTuner } from "./tuner.js";

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
const PLANE_PARAMS = {
  mass: 1100, wingArea: 16, maxThrust: 2600, cd0: 0.03, kInduced: 0.05, clMax: 1.45,
  maxRollRateDeg: 80, maxPitchRateDeg: 40, turnFactor: 0.7,
  cruiseKmh: 180, minSpeedKmh: 50, maxSpeedKmh: 340,
  camBack: 40, camUp: 12, camRollFollow: 0, flapForce: 0,
};
const VEHICLES = [
  { id: "plane", emoji: "✈️", name: "Plane", type: "plane", uri: "assets/plane.glb", scale: 0.09, yaw: -105, pitch: 0, roll: 0, params: PLANE_PARAMS },
];

const PRESETS = [
  { emoji: "🏙️", name: "Manhattan", desc: "Skyscraper canyons", lat: 40.758, lng: -73.9855 },
  { emoji: "🗼", name: "Tokyo Bay", desc: "Odaiba & the bay", lat: 35.6329, lng: 139.8804 },
  { emoji: "🏔️", name: "Swiss Alps", desc: "Over Interlaken", lat: 46.6863, lng: 7.8632 },
  { emoji: "🏜️", name: "Grand Canyon", desc: "Down the gorge", lat: 36.0544, lng: -112.1401 },
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
  quality: "performance", // default to playable FPS
};

const QUALITY = [
  { id: "performance", label: "Performance" },
  { id: "balanced", label: "Balanced" },
  { id: "quality", label: "Quality" },
];

// ================= Google Maps loader =================
window.initApp = initApp;

(function loadMaps() {
  const cfg = window.HORSEBACK_CONFIG;
  if (!cfg || !cfg.GOOGLE_MAPS_API_KEY || cfg.GOOGLE_MAPS_API_KEY === "YOUR_API_KEY_HERE") {
    showError("No Google Maps API key found. Copy config.example.js to config.js and add your key.");
    return;
  }
  if (!window.Cesium) {
    showError("Cesium failed to load (check your network).");
    return;
  }
  const s = document.createElement("script");
  s.src =
    "https://maps.googleapis.com/maps/api/js?key=" +
    encodeURIComponent(cfg.GOOGLE_MAPS_API_KEY) +
    "&libraries=places&callback=initApp&loading=async";
  s.async = true;
  s.onerror = () => showError("Failed to load Google Maps. Check your key and network.");
  document.head.appendChild(s);
})();

// ================= Init =================
function initApp() {
  dlog("maps loaded; init");
  renderVehicles();
  renderQuality();
  renderPresets();
  setupSearch();
  setupGeolocation();
  setupResult();
  setupTouch();
  setupTilt();
  renderBoard("landing-board");
  document.getElementById("btn-loading-cancel").addEventListener("click", cancelLoading);

  app.flight = new Flight("cesiumContainer");
  app.flight.onError = (e) => {
    const msg = (e && (e.message || e.toString())) || "unknown";
    showError("3D render error: " + msg + " (details in console, F12)");
  };
  dlog("creating Cesium viewer + 3D tileset…");
  app.sceneReady = app.flight
    .init(window.HORSEBACK_CONFIG.GOOGLE_MAPS_API_KEY)
    .then((f) => {
      dlog("3D tileset ready");
      return f;
    })
    .catch((err) => {
      dlog("TILESET FAILED: " + (err && (err.message || err)), true);
      showError("Couldn't start Google 3D Tiles. Ensure the Map Tiles API is enabled, then reload.");
      throw err;
    });

  app.hud = new HUD({
    onMute: () => app.hud.setMuted(app.audio.toggleMute()),
    onDismount: dismount,
  });
  app.hud.bind();

  app.controller = new Controller(app.flight.controls, {
    onDismount: dismount,
    onFlaps: () => app.flight.cycleFlaps(),
    onToggleMode: () => app.flight.toggleMode(),
  });

  app.tuner = buildTuner(app.flight.P);
  app.tuner.setDefaults(DEFAULT_PARAMS);
  const tuneBtn = document.getElementById("btn-tune");
  if (tuneBtn) tuneBtn.addEventListener("click", () => app.tuner.toggle());

  // Shared flight link → jump straight into the replay.
  const sharedId = new URLSearchParams(location.search).get("flight");
  if (sharedId) app.sceneReady.then(() => watchFlight(sharedId)).catch(() => showScreen("landing"));
  else showScreen("landing");
}

// ================= Landing =================
function renderVehicles() {
  const wrap = document.getElementById("vehicles");
  wrap.innerHTML = "";
  if (VEHICLES.length <= 1) {
    wrap.style.display = "none"; // only one vehicle → no picker needed
    return;
  }
  for (const v of VEHICLES) {
    const btn = document.createElement("button");
    btn.className = "vehicle-btn" + (v.id === app.vehicle.id ? " active" : "");
    btn.innerHTML = `<span class="v-emoji">${v.emoji}</span><span class="v-name">${v.name}</span>`;
    btn.addEventListener("click", () => {
      app.vehicle = v;
      for (const b of wrap.children) b.classList.remove("active");
      btn.classList.add("active");
    });
    wrap.appendChild(btn);
  }
}

function renderQuality() {
  const wrap = document.getElementById("quality");
  if (!wrap) return;
  wrap.innerHTML = '<span class="quality-cap">Graphics</span>';
  for (const q of QUALITY) {
    const btn = document.createElement("button");
    btn.className = "quality-btn" + (q.id === app.quality ? " active" : "");
    btn.textContent = q.label;
    btn.addEventListener("click", () => {
      app.quality = q.id;
      if (app.flight) app.flight.setQuality(q.id);
      for (const b of wrap.querySelectorAll(".quality-btn")) b.classList.remove("active");
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
    card.addEventListener("click", () => takeOff(p.lat, p.lng, p.name));
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
    takeOff(loc.lat(), loc.lng(), place.name || "your flight");
  });
}

// ---- Touch controls (mobile / tablet) ----
function setupTouch() {
  if (matchMedia("(pointer: coarse)").matches || "ontouchstart" in window || navigator.maxTouchPoints > 0) {
    document.body.classList.add("touch");
  }
  const clamp1 = (x) => Math.max(-1, Math.min(1, x));
  const joy = document.getElementById("joy");
  const knob = document.getElementById("joy-knob");
  let active = false;
  let cx = 0;
  let cy = 0;
  let R = 60;
  const steer = (roll, pitch) => {
    if (app.flight) {
      app.flight.controls.roll = roll;
      app.flight.controls.pitch = pitch;
    }
  };
  const start = (e) => {
    active = true;
    const r = joy.getBoundingClientRect();
    cx = r.left + r.width / 2;
    cy = r.top + r.height / 2;
    R = r.width / 2 - 8;
    move(e);
  };
  const move = (e) => {
    if (!active) return;
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
  const end = () => {
    active = false;
    knob.style.transform = "translate(0,0)";
    steer(0, 0);
  };
  joy.addEventListener("pointerdown", start);
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", end);
  window.addEventListener("pointercancel", end);

  const setThr = (v) => {
    if (app.flight) app.flight.controls.throttle = v;
  };
  const bindThr = (id, v) => {
    const el = document.getElementById(id);
    if (!el) return;
    const on = (e) => {
      e.preventDefault();
      setThr(v);
    };
    const off = () => setThr(0);
    el.addEventListener("pointerdown", on);
    el.addEventListener("pointerup", off);
    el.addEventListener("pointercancel", off);
    el.addEventListener("pointerleave", off);
  };
  bindThr("btn-accel", 1);
  bindThr("btn-decel", -1);
}

// ---- Tilt-to-steer (device gyroscope) ----
function setupTilt() {
  const btn = document.getElementById("btn-tilt");
  if (!btn) return;
  let enabled = false;
  let neutral = null;
  const clamp1 = (x) => Math.max(-1, Math.min(1, x));

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
    const S = 1 / 28; // ~28° tilt = full deflection
    app.flight.controls.roll = clamp1(roll * S);
    app.flight.controls.pitch = clamp1(pitch * S);
  };

  const setLabel = () => {
    btn.textContent = enabled ? "🎮 Tilt: ON" : "🎮 Tilt: OFF";
    btn.classList.toggle("on", enabled);
  };
  const enable = () => {
    neutral = null;
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
      (pos) => takeOff(pos.coords.latitude, pos.coords.longitude, "your location"),
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
  app.cancelled = false;
  app.flying = false;
  // Unlock/resume audio NOW, inside the click gesture — before the tile-load
  // await — or Safari leaves the context suspended and there's no engine sound.
  app.audio.start();

  showScreen("ride");
  if (app.flight.viewer) app.flight.viewer.resize();
  showLoading(true, `Prepping flight over ${label}…`);

  try {
    await app.sceneReady;
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
    setLandingStatus(err.message || "Couldn't start that flight. Try another spot.", true);
  }
}

function beginFlight() {
  Object.assign(app.flight.controls, { pitch: 0, roll: 0, rudder: 0, throttle: 0, level: false });
  app.audio.start();
  app.hud.setMuted(app.audio.muted);
  app.controller.bind();

  app.flight.onState = (s) => {
    app.hud.update(s);
    app.audio.setThrottle(s.throttle);
    app.audio.setSpeed(Math.max(0, Math.min(1, (s.speedKmh / 3.6 - 11) / (97 - 11))));
  };

  app.flying = true;
  app.flight.start();
}

function dismount() {
  const wasFlying = app.flying;
  const flight = app.flight ? app.flight.getFlight() : null;
  app.flying = false;
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
      const data = await res.json(); // { id, board }
      renderBoardData("result-board", data.board, name.toUpperCase());
      document.getElementById("result-submit-row").style.display = "none";
      showShare(data.id);
    } catch (e) {
      btn.disabled = false;
      setLandingStatus("Couldn't submit score (server offline?).", true);
    }
  });
  document.getElementById("btn-result-again").addEventListener("click", goLanding);
  document.getElementById("btn-share-copy").addEventListener("click", () => {
    const link = document.getElementById("share-link").value;
    navigator.clipboard && navigator.clipboard.writeText(link);
    const b = document.getElementById("btn-share-copy");
    b.textContent = "Copied!";
    setTimeout(() => (b.textContent = "Copy link"), 1500);
  });
}

function showShare(id) {
  if (!id) return;
  const link = location.origin + location.pathname + "?flight=" + id;
  document.getElementById("share-link").value = link;
  document.getElementById("result-share").style.display = "";
}

// ---- Watch a saved flight (replay) ----
async function watchFlight(id) {
  app.flying = false;
  showScreen("ride");
  if (app.flight.viewer) app.flight.viewer.resize();
  showLoading(true, "Loading flight…");
  try {
    await app.sceneReady;
    const r = await fetch("/api/flight?id=" + encodeURIComponent(id));
    const flight = await r.json();
    if (!flight || !flight.path || !flight.path.length) throw new Error("not found");
    app.flight.onReplayEnd = () => {
      app.flight.dispose();
      goLanding();
    };
    await app.flight.startReplay(flight.path, (f, l) => setLoading(f, l));
    showLoading(false);
  } catch (e) {
    console.error(e);
    showLoading(false);
    goLanding();
    setLandingStatus("Couldn't load that flight.", true);
  }
}

function goLanding() {
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
        ${s.id ? `<button class="board-watch" data-id="${s.id}" title="Watch this flight">▶</button>` : ""}
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
  const m = Math.floor(sec / 60);
  const s = Math.round(sec % 60);
  return m + ":" + String(s).padStart(2, "0");
}

function cancelLoading() {
  app.cancelled = true;
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
