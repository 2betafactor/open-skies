// audio.js — WebAudio flight sound: a throttle-responsive engine and speed-
// responsive wind, mixed quietly enough to sit under Nightride FM (radio.js).
// The HUD's mute button silences this layer; say() stays a no-op hook.
export class EngineAudio {
  constructor() {
    this.muted = false;
    this._ctx = null;
    this._built = false;
    this._type = "plane";
  }

  // Must be called from a user gesture (takeOff click does) so Safari resumes.
  async start() {
    try {
      if (!this._ctx) this._ctx = new (window.AudioContext || window.webkitAudioContext)();
      if (this._ctx.state === "suspended") await this._ctx.resume();
      if (!this._built) this._build();
      this._applyMute();
    } catch (e) {
      /* audio unavailable — the game flies fine silent */
    }
  }

  suspend() {
    try {
      if (this._ctx && this._ctx.state === "running") this._ctx.suspend();
    } catch (e) {}
  }

  _build() {
    const ctx = this._ctx;
    this._master = ctx.createGain();
    this._master.gain.value = 1;
    this._master.connect(ctx.destination);

    // Engine hum: two detuned oscillators through a lowpass — reads as a
    // turbine at low throttle, a harder snarl at full power.
    this._oscA = ctx.createOscillator();
    this._oscB = ctx.createOscillator();
    this._oscA.type = this._oscB.type = this._type === "spaceship" ? "sine" : "sawtooth";
    this._engineLp = ctx.createBiquadFilter();
    this._engineLp.type = "lowpass";
    this._engineLp.frequency.value = 420;
    this._engineGain = ctx.createGain();
    this._engineGain.gain.value = 0.05;
    this._oscA.connect(this._engineLp);
    this._oscB.connect(this._engineLp);
    this._engineLp.connect(this._engineGain);
    this._engineGain.connect(this._master);

    // Shared looped noise source feeds the turbine whine and the wind.
    const len = 2 * ctx.sampleRate;
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    this._noise = ctx.createBufferSource();
    this._noise.buffer = buf;
    this._noise.loop = true;

    // Whine: bandpassed noise that rises with throttle (jet spool).
    this._whineBp = ctx.createBiquadFilter();
    this._whineBp.type = "bandpass";
    this._whineBp.frequency.value = 1400;
    this._whineBp.Q.value = 6;
    this._whineGain = ctx.createGain();
    this._whineGain.gain.value = 0.008;
    this._noise.connect(this._whineBp);
    this._whineBp.connect(this._whineGain);
    this._whineGain.connect(this._master);

    // Wind: broad noise band that opens up with airspeed.
    this._windBp = ctx.createBiquadFilter();
    this._windBp.type = "bandpass";
    this._windBp.frequency.value = 500;
    this._windBp.Q.value = 0.4;
    this._windGain = ctx.createGain();
    this._windGain.gain.value = 0.02;
    this._noise.connect(this._windBp);
    this._windBp.connect(this._windGain);
    this._windGain.connect(this._master);

    this._oscA.start();
    this._oscB.start();
    this._noise.start();
    this._built = true;
    this.setAircraft(this._type);
  }

  setAircraft(type) {
    this._type = type || "plane";
    if (!this._built) return;
    const wave = this._type === "spaceship" ? "sine" : "sawtooth";
    this._oscA.type = wave;
    this._oscB.type = wave;
    this._base = this._type === "spaceship" ? 130 : this._type === "balloon" ? 0 : 62;
    if (this._base === 0) this._engineGain.gain.value = 0; // balloons drift silently
  }

  // t: 0..1 throttle. Smoothed so the engine spools rather than clicks.
  setThrottle(t) {
    if (!this._built || !this._ctx) return;
    const now = this._ctx.currentTime;
    const base = this._base === undefined ? 62 : this._base;
    if (base > 0) {
      const f = base * (0.75 + t * 1.25);
      this._oscA.frequency.setTargetAtTime(f, now, 0.25);
      this._oscB.frequency.setTargetAtTime(f * 1.012 + 1.5, now, 0.25); // beat/detune
      this._engineLp.frequency.setTargetAtTime(280 + t * 900, now, 0.25);
      this._engineGain.gain.setTargetAtTime(0.035 + t * 0.075, now, 0.3);
      this._whineBp.frequency.setTargetAtTime(900 + t * 2200, now, 0.4);
      this._whineGain.gain.setTargetAtTime(0.004 + t * 0.02, now, 0.4);
    }
  }

  // f: 0..1 speed fraction. Wind builds as the square (quiet at cruise).
  setSpeed(f) {
    if (!this._built || !this._ctx) return;
    const now = this._ctx.currentTime;
    const x = Math.max(0, Math.min(1, f));
    this._windGain.gain.setTargetAtTime(0.01 + x * x * 0.16, now, 0.3);
    this._windBp.frequency.setTargetAtTime(350 + x * 1400, now, 0.3);
  }

  say() {}

  _applyMute() {
    if (this._master) this._master.gain.value = this.muted ? 0 : 1;
  }

  toggleMute() {
    this.muted = !this.muted;
    this._applyMute();
    return this.muted;
  }
}
