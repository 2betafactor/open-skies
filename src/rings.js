// rings.js — "Ring Run": a checkpoint course of glowing rings laid out ahead
// of the spawn point. Client-only; free flight stays the default activity.

const RING_COUNT = 8;
const RING_RADIUS = 55; // metres (visual)
const PASS_DIST = 65; // metres (generous arcade pass detection)
const SPACING = 900; // metres between rings

export class RingRun {
  constructor(flight, notify) {
    this.flight = flight;
    this.notify = notify;
    this.active = false;
    this.rings = [];
    this.finishedAt = 0;
  }

  start() {
    const f = this.flight;
    this.clear();
    if (!f.viewer || !f.spawnLL) return;
    this.active = true;
    this.startTime = performance.now();
    this.finishedAt = 0;
    this.collected = 0;

    // A gentle S-curve ahead of the spawn heading (north), varied altitude.
    const D2R = Math.PI / 180;
    let lat = f.spawnLL.lat;
    let lng = f.spawnLL.lng;
    let alt = f.spawnGround + 350;
    let bearing = 0;
    for (let i = 0; i < RING_COUNT; i++) {
      if (i > 0) bearing += (i % 2 ? 1 : -1) * 0.25;
      lat += (Math.cos(bearing) * SPACING) / 111320;
      lng += (Math.sin(bearing) * SPACING) / (111320 * Math.cos(lat * D2R));
      alt += ((i % 3) - 1) * 110;
      alt = Math.max(f.spawnGround + 160, alt);
      this.rings.push(this._addRing(lat, lng, alt, bearing));
    }
    this.notify(`Ring run: fly through all ${RING_COUNT} rings!`);
  }

  _addRing(lat, lng, alt, bearing) {
    const C = window.Cesium;
    const center = C.Cartesian3.fromDegrees(lng, lat, alt);
    const enu = C.Transforms.eastNorthUpToFixedFrame(center, C.Ellipsoid.WGS84, new C.Matrix4());
    const positions = [];
    for (let a = 0; a <= 32; a++) {
      const t = (a / 32) * Math.PI * 2;
      const rx = Math.cos(t) * RING_RADIUS; // across the course
      const ry = Math.sin(t) * RING_RADIUS; // up
      const local = new C.Cartesian3(Math.cos(bearing) * rx, -Math.sin(bearing) * rx, ry);
      positions.push(C.Matrix4.multiplyByPoint(enu, local, new C.Cartesian3()));
    }
    const entity = this.flight.viewer.entities.add({
      polyline: {
        positions,
        width: 10,
        material: new C.PolylineGlowMaterialProperty({
          glowPower: 0.25,
          color: C.Color.fromCssColorString("#ffd54f"),
        }),
      },
    });
    return { entity, center, done: false };
  }

  // Called each HUD update; returns the course status line ('' when inactive).
  update() {
    if (!this.active) return "";
    const C = window.Cesium;
    const pos = this.flight.position;
    if (pos && !this.finishedAt) {
      for (const r of this.rings) {
        if (!r.done && C.Cartesian3.distance(pos, r.center) < PASS_DIST) {
          r.done = true;
          this.collected++;
          r.entity.polyline.material = new C.PolylineGlowMaterialProperty({
            glowPower: 0.18,
            color: C.Color.fromCssColorString("#69f0ae"),
          });
          if (navigator.vibrate) navigator.vibrate(30);
          if (this.collected === this.rings.length) {
            this.finishedAt = performance.now();
            this.notify(`Course complete — ${fmt(this.finishedAt - this.startTime)}! 🏁`);
          } else {
            this.notify(`Ring ${this.collected}/${this.rings.length} ✓`);
          }
        }
      }
    }
    const elapsed = (this.finishedAt || performance.now()) - this.startTime;
    return this.finishedAt
      ? `🏁 ${fmt(elapsed)}`
      : `⭕ ${this.collected}/${this.rings.length} · ${fmt(elapsed)}`;
  }

  result() {
    if (!this.active) return null;
    return { collected: this.collected, total: this.rings.length, timeMs: (this.finishedAt || performance.now()) - this.startTime, complete: !!this.finishedAt };
  }

  clear() {
    for (const r of this.rings) {
      try { this.flight.viewer.entities.remove(r.entity); } catch (e) {}
    }
    this.rings = [];
    this.active = false;
  }
}

function fmt(ms) {
  const s = Math.max(0, Math.floor(ms / 1000));
  return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
}
