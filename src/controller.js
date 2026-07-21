// controller.js — keyboard input → shared `controls` object read by the flight
// engine. (Touch controls are a follow-up.)

const NAV_CODES = new Set([
  "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Space", "Minus", "Equal",
]);

export class Controller {
  constructor(controls, opts = {}) {
    this.controls = controls;
    this.onDismount = opts.onDismount || (() => {});
    this.onFlaps = opts.onFlaps || (() => {});
    this.onToggleMode = opts.onToggleMode || (() => {});
    this.keys = new Set();
    this._bound = false;
    this._kd = (e) => this._down(e);
    this._ku = (e) => this._up(e);
    this._blur = () => {
      this.keys.clear();
      this._apply();
    };
  }

  bind() {
    if (this._bound) return;
    this._bound = true;
    window.addEventListener("keydown", this._kd);
    window.addEventListener("keyup", this._ku);
    window.addEventListener("blur", this._blur);
  }

  unbind() {
    window.removeEventListener("keydown", this._kd);
    window.removeEventListener("keyup", this._ku);
    window.removeEventListener("blur", this._blur);
    // Clear any held keys so a control doesn't stay stuck into the next flight.
    this.keys.clear();
    this._apply();
    this._bound = false;
  }

  _down(e) {
    if (e.code === "Escape") return this.onDismount();
    if (e.code === "KeyF" && !e.repeat) this.onFlaps();
    if (e.code === "KeyV" && !e.repeat) this.onToggleMode();
    if (NAV_CODES.has(e.code)) e.preventDefault();
    this.keys.add(e.code);
    this._apply();
  }

  _up(e) {
    this.keys.delete(e.code);
    this._apply();
  }

  _apply() {
    const k = this.keys;
    const c = this.controls;
    const on = (...codes) => (codes.some((x) => k.has(x)) ? 1 : 0);
    c.pitch = on("ArrowUp", "KeyW") - on("ArrowDown", "KeyS"); // + = nose up (climb)
    c.roll = on("ArrowRight", "KeyD") - on("ArrowLeft", "KeyA"); // + = roll right
    c.rudder = on("KeyE") - on("KeyQ");
    c.throttle =
      on("ShiftLeft", "ShiftRight", "Equal", "NumpadAdd") -
      on("ControlLeft", "ControlRight", "Minus", "NumpadSubtract");
    c.level = !!on("Space");
  }
}
