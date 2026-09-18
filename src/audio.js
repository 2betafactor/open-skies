// Audio bridge kept for the HUD. Flight ambience is silent; Nightride FM is
// the only sound source and is managed by radio.js.
export class EngineAudio {
  constructor(){this.muted=false;this._shouldPlay=false;}
  async start(){this._shouldPlay=true;}
  suspend(){this._shouldPlay=false;}
  setAircraft(){}
  setThrottle(){}
  setSpeed(){}
  say(){}
  toggleMute(){this.muted=!this.muted;return this.muted;}
}
