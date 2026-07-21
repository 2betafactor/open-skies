// tuner.js — a tiny self-contained slider panel for live flight-feel tuning.
// No external dependency. Toggle with the "g" key or the ⚙ button.

const SPEC = [
  { k: "modelYawDeg", label: "★ model yaw", min: -180, max: 180, step: 5 },
  { k: "modelPitchDeg", label: "★ model pitch", min: -90, max: 90, step: 1 },
  { k: "modelRollDeg", label: "★ model roll", min: -180, max: 180, step: 5 },
  { k: "minSpeedKmh", label: "min speed", min: 20, max: 120, step: 5 },
  { k: "cruiseKmh", label: "cruise speed", min: 60, max: 260, step: 5 },
  { k: "maxSpeedKmh", label: "max speed", min: 150, max: 500, step: 10 },
  { k: "maxRollRateDeg", label: "roll rate", min: 20, max: 180, step: 5 },
  { k: "maxPitchRateDeg", label: "pitch rate", min: 10, max: 90, step: 5 },
  { k: "rudderRateDeg", label: "rudder rate", min: 0, max: 60, step: 5 },
  { k: "rotEase", label: "rot inertia", min: 2, max: 20, step: 0.5 },
  { k: "energyFactor", label: "energy (dive/climb)", min: 0, max: 1, step: 0.05 },
  { k: "turnFactor", label: "turn strength", min: 0.1, max: 1.6, step: 0.05 },
  { k: "turnBleed", label: "turn bleed", min: 0, max: 0.2, step: 0.01 },
  { k: "velLag", label: "velocity lag (s)", min: 0.05, max: 1.2, step: 0.05 },
  { k: "throttleLag", label: "throttle lag (s)", min: 0.3, max: 4, step: 0.1 },
  { k: "autoFreq", label: "auto-level freq", min: 0.5, max: 5, step: 0.1 },
  { k: "autoDamp", label: "auto-level damp", min: 0.2, max: 1.2, step: 0.05 },
  { k: "pitchClampDeg", label: "pitch limit", min: 20, max: 85, step: 5 },
  { k: "rollClampDeg", label: "roll limit", min: 30, max: 90, step: 5 },
  { k: "ambientDeg", label: "ambient drift", min: 0, max: 2, step: 0.1 },
  { k: "camBack", label: "cam back", min: 5, max: 90, step: 1 },
  { k: "camUp", label: "cam up", min: 1, max: 40, step: 0.5 },
  { k: "camTau", label: "cam lag (s)", min: 0.02, max: 0.5, step: 0.02 },
  { k: "camLookAhead", label: "cam look-ahead", min: 0, max: 30, step: 1 },
  { k: "camRollFollow", label: "cam roll-follow", min: 0, max: 1, step: 0.05 },
  { k: "fovMinDeg", label: "FOV min", min: 40, max: 90, step: 1 },
  { k: "fovMaxDeg", label: "FOV max", min: 50, max: 110, step: 1 },
  { k: "mass", label: "◆ sim mass kg", min: 500, max: 3000, step: 50 },
  { k: "wingArea", label: "◆ wing area m²", min: 8, max: 30, step: 1 },
  { k: "maxThrust", label: "◆ max thrust N", min: 1000, max: 6000, step: 100 },
  { k: "cd0", label: "◆ parasitic drag", min: 0.015, max: 0.08, step: 0.005 },
  { k: "kInduced", label: "◆ induced drag", min: 0.02, max: 0.12, step: 0.005 },
  { k: "clMax", label: "◆ CL max", min: 1.0, max: 2.2, step: 0.05 },
  { k: "trimAoADeg", label: "◆ trim AoA", min: 0, max: 6, step: 0.5 },
  { k: "weathervane", label: "◆ weathervane", min: 0, max: 6, step: 0.2 },
  { k: "pitchStab", label: "◆ pitch stability", min: 0, max: 4, step: 0.1 },
  { k: "rollDamp", label: "◆ roll damping", min: 0, max: 5, step: 0.1 },
];

export function buildTuner(params) {
  const panel = document.createElement("div");
  panel.className = "tuner";
  panel.innerHTML = `<div class="tuner-head">✈ Flight tuner <span class="tuner-hint">(g to toggle)</span></div>`;
  const body = document.createElement("div");
  body.className = "tuner-body";
  panel.appendChild(body);

  const rows = {};
  for (const s of SPEC) {
    const row = document.createElement("label");
    row.className = "tuner-row";
    const name = document.createElement("span");
    name.className = "tuner-name";
    name.textContent = s.label;
    const val = document.createElement("span");
    val.className = "tuner-val";
    const input = document.createElement("input");
    input.type = "range";
    input.min = s.min;
    input.max = s.max;
    input.step = s.step;
    input.value = params[s.k];
    val.textContent = fmt(params[s.k]);
    input.addEventListener("input", () => {
      const v = parseFloat(input.value);
      params[s.k] = v;
      val.textContent = fmt(v);
    });
    row.append(name, input, val);
    body.appendChild(row);
    rows[s.k] = { input, val };
  }

  const reset = document.createElement("button");
  reset.className = "tuner-reset";
  reset.textContent = "Reset defaults";
  panel.appendChild(reset);

  document.body.appendChild(panel);

  const toggle = () => panel.classList.toggle("show");
  window.addEventListener("keydown", (e) => {
    if (e.code === "KeyG" && !e.repeat) toggle();
  });

  return {
    panel,
    toggle,
    setDefaults(defaults) {
      reset.onclick = () => {
        for (const s of SPEC) {
          params[s.k] = defaults[s.k];
          rows[s.k].input.value = defaults[s.k];
          rows[s.k].val.textContent = fmt(defaults[s.k]);
        }
      };
    },
  };
}

function fmt(v) {
  return Math.abs(v) < 10 ? String(Math.round(v * 100) / 100) : String(Math.round(v));
}
