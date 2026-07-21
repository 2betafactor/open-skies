// audio.js — calm ambient BACKGROUND MUSIC (evolving chord pads through reverb),
// with a faint wind bed that rises with speed. No engine noise. Web Audio only;
// must be started from a user gesture (Take Off). Interface kept the same so the
// rest of the app doesn't change: start / setThrottle / setSpeed / toggleMute.

// A gentle, cinematic loop: Am – F – C – G. Four voices, one note each.
const CHORDS = [
  [220.0, 261.63, 329.63, 440.0], // Am  (A3 C4 E4 A4)
  [174.61, 220.0, 261.63, 349.23], // F   (F3 A3 C4 F4)
  [196.0, 261.63, 329.63, 392.0], // C/G (G3 C4 E4 G4)
  [196.0, 246.94, 293.66, 392.0], // G   (G3 B3 D4 G4)
];
const BASS = [110.0, 87.31, 130.81, 98.0]; // A2 F2 C3 G2
const CHORD_SEC = 9;

export class EngineAudio {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.padLp = null;
    this.voices = [];
    this.bass = null;
    this.windGain = null;
    this.muted = false;
    this._started = false;
    this._chordTimer = null;
    this._idx = 0;
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
    this.master.gain.value = this.muted ? 0 : 0.55;
    this.master.connect(ctx.destination);

    // Reverb for space.
    const reverb = ctx.createConvolver();
    reverb.buffer = makeImpulse(ctx, 2.6, 2.2);
    const wet = ctx.createGain();
    wet.gain.value = 0.55;
    reverb.connect(wet).connect(this.master);

    // Shared warm lowpass for the pads.
    this.padLp = ctx.createBiquadFilter();
    this.padLp.type = "lowpass";
    this.padLp.frequency.value = 1100;
    this.padLp.Q.value = 0.4;
    const padBus = ctx.createGain();
    padBus.gain.value = 0.9;
    this.padLp.connect(padBus);
    padBus.connect(this.master); // dry
    padBus.connect(reverb); // wet

    // Slow filter LFO for gentle movement.
    const lfo = ctx.createOscillator();
    lfo.frequency.value = 0.05;
    const lfoGain = ctx.createGain();
    lfoGain.gain.value = 300;
    lfo.connect(lfoGain).connect(this.padLp.frequency);
    lfo.start();

    // Four detuned pad voices.
    for (let v = 0; v < 4; v++) {
      const g = ctx.createGain();
      g.gain.value = 0.16;
      g.connect(this.padLp);
      const o1 = ctx.createOscillator();
      o1.type = "triangle";
      const o2 = ctx.createOscillator();
      o2.type = "sine";
      o2.detune.value = 6; // slight chorus
      o1.connect(g);
      o2.connect(g);
      o1.start();
      o2.start();
      this.voices.push({ oscs: [o1, o2] });
    }

    // Soft sub bass following the chord root.
    this.bass = ctx.createOscillator();
    this.bass.type = "sine";
    const bg = ctx.createGain();
    bg.gain.value = 0.16;
    this.bass.connect(bg).connect(this.master);
    this.bass.start();

    // Faint wind bed — volume follows speed (set via setSpeed).
    const noise = ctx.createBufferSource();
    noise.buffer = makeNoise(ctx, 2);
    noise.loop = true;
    const wbp = ctx.createBiquadFilter();
    wbp.type = "bandpass";
    wbp.frequency.value = 500;
    wbp.Q.value = 0.4;
    this.windGain = ctx.createGain();
    this.windGain.gain.value = 0.02;
    noise.connect(wbp).connect(this.windGain).connect(this.master);
    noise.start();

    this._started = true;
    this._idx = 0;
    this._setChord(0);
    this._chordTimer = setInterval(() => this._setChord(++this._idx), CHORD_SEC * 1000);
  }

  _setChord(i) {
    if (!this._started) return;
    const now = this.ctx.currentTime;
    const chord = CHORDS[i % CHORDS.length];
    for (let v = 0; v < this.voices.length; v++) {
      const f = chord[v % chord.length];
      this.voices[v].oscs.forEach((o) => o.frequency.setTargetAtTime(f, now, 1.6));
    }
    this.bass.frequency.setTargetAtTime(BASS[i % BASS.length], now, 1.6);
  }

  // Music is independent of throttle — no-op (kept for interface compatibility).
  setThrottle() {}

  // Speed gently brightens the music and lifts the wind.
  setSpeed(frac) {
    if (!this._started) return;
    const now = this.ctx.currentTime;
    this.windGain.gain.setTargetAtTime(0.02 + frac * 0.1, now, 0.5);
  }

  toggleMute() {
    this.muted = !this.muted;
    if (this._started) {
      this.master.gain.setTargetAtTime(this.muted ? 0 : 0.55, this.ctx.currentTime, 0.08);
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
  const d = buf.getChannelData(0);
  for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
  return buf;
}

function makeImpulse(ctx, seconds, decay) {
  const len = Math.floor(ctx.sampleRate * seconds);
  const buf = ctx.createBuffer(2, len, ctx.sampleRate);
  for (let ch = 0; ch < 2; ch++) {
    const d = buf.getChannelData(ch);
    for (let i = 0; i < len; i++) {
      d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
    }
  }
  return buf;
}
