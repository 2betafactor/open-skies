// hud.js — flight HUD: airspeed, altitude, heading, throttle, warnings.

const COMPASS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];

export class HUD {
  constructor(handlers = {}) {
    this.onMute = handlers.onMute || (() => {});
    this.onDismount = handlers.onDismount || (() => {});
    this.el = {
      airspeed: document.getElementById("hud-airspeed"),
      altitude: document.getElementById("hud-altitude"),
      heading: document.getElementById("hud-heading"),
      compass: document.getElementById("hud-compass"),
      throttle: document.getElementById("hud-throttle-bar"),
      warning: document.getElementById("hud-warning"),
      crashes: document.getElementById("hud-crashes"),
      vspeed: document.getElementById("hud-sim"),
      attRotate: document.getElementById("att-rotate"),
      attInner: document.getElementById("att-inner"),
      mute: document.getElementById("btn-mute"),
    };
    this._bound = false;
  }

  bind() {
    if (this._bound) return;
    this._bound = true;
    this.el.mute.addEventListener("click", () => this.onMute());
    document.getElementById("btn-dismount").addEventListener("click", () => this.onDismount());
  }

  setMuted(muted) {
    this.el.mute.textContent = muted ? "🔇" : "🔊";
  }

  update(s) {
    this.el.airspeed.textContent = Math.round(s.speedKmh) + " km/h";
    this.el.altitude.textContent = Math.round(s.altM).toLocaleString() + " m";
    const hd = Math.round(s.headingDeg);
    this.el.heading.textContent = hd + "°";
    this.el.compass.textContent = COMPASS[Math.round(hd / 45) % 8];
    this.el.throttle.style.width = Math.round(s.throttle * 100) + "%";
    if (s.warning) {
      this.el.warning.textContent = s.warning;
      this.el.warning.classList.add("show");
    } else {
      this.el.warning.classList.remove("show");
    }
    this.el.crashes.textContent = s.crashes ? "✈✕ " + s.crashes : "";

    // Attitude indicator: horizon rolls opposite the bank, drops as the nose rises.
    if (this.el.attRotate) this.el.attRotate.style.transform = `rotate(${-(s.rollDeg || 0)}deg)`;
    if (this.el.attInner) this.el.attInner.style.transform = `translateY(${(s.pitchDeg || 0) * 1.6}px)`;

    if (this.el.vspeed) {
      const parts = [];
      if (s.homeKm != null) parts.push("📍 " + s.homeKm.toFixed(1) + " km");
      const v = Math.round(s.vspeed || 0);
      parts.push("V/S " + (v >= 0 ? "+" : "") + v + " m/s");
      if (s.flaps) parts.push("FLAPS " + s.flaps + "°");
      this.el.vspeed.textContent = parts.join("   ·   ");
    }
  }
}
