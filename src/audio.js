// audio.js — synthesized single-prop aircraft engine: layered detuned oscillators
// through a lowpass, a subtle prop "chop" amplitude modulation, a faint high
// whine, and wind that scales with speed. Everything revs with throttle.
// Web Audio only; must be started from a user gesture (Take Off).

export class EngineAudio {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.engineGain = null;
    this.lp = null;
    this.osc = [];
    this.chop = null;
    this.whine = null;
    this.windGain = null;
    this.muted = false;
    this._started = false;
  }

  async start() {
    if (this._started) {
      if (this.ctx.state === "suspended") await this.ctx.resume();
      return;
    }
    const Ctx = window.AudioContext || window.webkitAudioContext;
    this.ctx = new Ctx();
    if (this.ctx.state === "suspended") await this.ctx.resume();
    const ctx = this.ctx;

    this.master = ctx.createGain();
    this.master.gain.value = this.muted ? 0 : 0.85;
    this.master.connect(ctx.destination);

    // Engine core: detuned saws + a sub, through a lowpass, chopped by the prop.
    this.lp = ctx.createBiquadFilter();
    this.lp.type = "lowpass";
    this.lp.frequency.value = 650;
    this.lp.Q.value = 0.7;
    this.lp.connect(this.master);

    this.engineGain = ctx.createGain();
    this.engineGain.gain.value = 0.42; // base; the chop LFO swings this a little
    this.engineGain.connect(this.lp);

    const mix = ctx.createGain();
    mix.gain.value = 0.5;
    mix.connect(this.engineGain);
    const o1 = ctx.createOscillator(); o1.type = "sawtooth"; o1.frequency.value = 60;
    const o2 = ctx.createOscillator(); o2.type = "sawtooth"; o2.frequency.value = 90;
    const o3 = ctx.createOscillator(); o3.type = "triangle"; o3.frequency.value = 30;
    this.osc = [o1, o2, o3];
    o1.connect(mix); o2.connect(mix); o3.connect(mix);

    // Prop chop — gentle amplitude modulation (NOT the old flutter).
    this.chop = ctx.createOscillator();
    this.chop.type = "sine";
    this.chop.frequency.value = 24;
    const chopDepth = ctx.createGain();
    chopDepth.gain.value = 0.16;
    this.chop.connect(chopDepth).connect(this.engineGain.gain);

    // Faint high whine for "spinning metal".
    this.whine = ctx.createOscillator();
    this.whine.type = "sawtooth";
    this.whine.frequency.value = 800;
    const whineHp = ctx.createBiquadFilter();
    whineHp.type = "highpass";
    whineHp.frequency.value = 600;
    const whineGain = ctx.createGain();
    whineGain.gain.value = 0.035;
    this.whine.connect(whineHp).connect(whineGain).connect(this.master);

    // Wind — noise bed, volume follows speed.
    const noise = ctx.createBufferSource();
    noise.buffer = makeNoise(ctx, 1.5);
    noise.loop = true;
    const wbp = ctx.createBiquadFilter();
    wbp.type = "bandpass";
    wbp.frequency.value = 550;
    wbp.Q.value = 0.6;
    this.windGain = ctx.createGain();
    this.windGain.gain.value = 0.03;
    noise.connect(wbp).connect(this.windGain).connect(this.master);

    o1.start(); o2.start(); o3.start();
    this.chop.start();
    this.whine.start();
    noise.start();

    this._started = true;
    this.setThrottle(0.5);
  }

  setThrottle(t) {
    if (!this._started) return;
    const now = this.ctx.currentTime;
    const base = 55 + t * 75; // 55–130 Hz fundamental (idle → full)
    const T = 0.12;
    this.osc[0].frequency.setTargetAtTime(base, now, T);
    this.osc[1].frequency.setTargetAtTime(base * 1.5, now, T);
    this.osc[2].frequency.setTargetAtTime(base * 0.5, now, T);
    this.chop.frequency.setTargetAtTime(18 + t * 34, now, T); // blade rate rises with revs
    this.lp.frequency.setTargetAtTime(420 + t * 750, now, 0.15);
    this.whine.frequency.setTargetAtTime(700 + t * 1000, now, T);
    this.engineGain.gain.setTargetAtTime(0.32 + t * 0.2, now, 0.2);
  }

  setSpeed(frac) {
    if (!this._started) return;
    this.windGain.gain.setTargetAtTime(0.025 + frac * 0.12, this.ctx.currentTime, 0.3);
  }

  toggleMute() {
    this.muted = !this.muted;
    if (this._started) {
      this.master.gain.setTargetAtTime(this.muted ? 0 : 0.85, this.ctx.currentTime, 0.05);
    }
    return this.muted;
  }

  suspend() {
    if (this.ctx && this.ctx.state === "running") this.ctx.suspend();
  }
}

function makeNoise(ctx, seconds) {
  const len = Math.floor(ctx.sampleRate * seconds);
  const buf = ctx.createBuffer(1, len, ctx.sampleRate);
  const data = buf.getChannelData(0);
  for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  return buf;
}
