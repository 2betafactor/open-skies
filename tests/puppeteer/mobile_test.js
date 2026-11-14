#!/usr/bin/env node
// Puppeteer phone test for Open Skies: emulates real phones (iPhone 13 and
// Pixel 5, touch + mobile user agent), taps PLAY on the canvas like a user,
// waits for the fight, taps FIRE / ROCKET, drags to steer, measures the
// frame rate the page reports, and saves screenshots.
//
//   node tests/puppeteer/mobile_test.js [--url http://localhost:8000/play/] [--device "iPhone 13"]
//
// Uses the Chromium that Playwright installed (puppeteer-core, no download).
// Software WebGL here, so frame rates are far below a real phone; what this
// checks is that the flow and the controls work on a phone-shaped browser.
const puppeteer = require("puppeteer-core");
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const URL = opt("--url", "http://localhost:8000/play/?quality=Performance&scale=0.35&preload=600&horizon=0");
const DEVICES = opt("--device", "iPhone 13,Pixel 5").split(",");
const CHROME = process.env.CHROME || `${process.env.HOME}/.cache/ms-playwright/chromium-1228/chrome-linux64/chrome`;
const OUT = path.join(__dirname, "..", "out");
fs.mkdirSync(OUT, { recursive: true });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let fails = 0;
function check(ok, what) { console.log((ok ? "  ok   " : "  FAIL ") + what); if (!ok) fails++; }

async function snap(page) { return page.evaluate(() => (window.openskies ? window.openskies() : null)); }

async function touchHold(client, x, y, ms) {
  await client.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y, id: 1 }] });
  await sleep(ms);
}
async function touchRelease(client) {
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
}
async function touchDrag(client, x0, y0, x1, y1, ms) {
  await client.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: x0, y: y0, id: 2 }] });
  const steps = 8;
  for (let i = 1; i <= steps; i++) {
    const k = i / steps;
    await client.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: x0 + (x1 - x0) * k, y: y0 + (y1 - y0) * k, id: 2 }] });
    await sleep(40);
  }
  await sleep(ms);
}

async function runDevice(browser, name) {
  const device = puppeteer.KnownDevices[name];
  if (!device) { console.log("unknown device " + name); fails++; return; }
  console.log(`\n== ${name} (${device.viewport.width}x${device.viewport.height} @${device.viewport.deviceScaleFactor}x, landscape)`);
  const page = await browser.newPage();
  // Landscape: swap the viewport.
  await page.emulate({ ...device, viewport: { ...device.viewport, width: device.viewport.height, height: device.viewport.width, isLandscape: true } });
  const errors = [];
  page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  const client = await page.target().createCDPSession();
  const t0 = Date.now();
  await page.goto(URL, { waitUntil: "load", timeout: 120000 });
  let s = null;
  for (let i = 0; i < 240 && !s; i++) { s = await snap(page); if (!s) await sleep(500); }
  check(!!s, `engine booted in ${((Date.now() - t0) / 1000).toFixed(1)}s`);
  if (!s) { await page.close(); return; }
  check(s.mobile === true, `detected as a phone (ui scale ${(s.ui_scale || 0).toFixed(2)})`);
  // Wait for the menu to be ready (server config + tileset root), then tap PLAY where it is drawn.
  for (let i = 0; i < 120; i++) { s = await snap(page); if (s.tiles_state === "ready") break; await sleep(500); }
  check(s.tiles_state === "ready", `tileset ready (${s.tiles_state} ${s.tiles_error || ""})`);
  await page.screenshot({ path: path.join(OUT, `pptr_${name.replace(/\s/g, "_")}_menu.png`) });
  const dpr = s.dpr || device.viewport.deviceScaleFactor;
  const play = (s.menu_buttons || {}).play;
  check(!!play, "PLAY button located on the canvas");
  if (play) {
    const px = (play[0] + play[2] / 2) / dpr, py = (play[1] + play[3] / 2) / dpr;
    await page.touchscreen.tap(px, py);
    console.log(`    tapped PLAY at ${px.toFixed(0)},${py.toFixed(0)} css px`);
  }
  await sleep(1500);
  s = await snap(page);
  check(s.state === "PREPARING" || s.state === "RUN", `PLAY started the game (state ${s.state})`);
  // Wait for the fight.
  const tStart = Date.now();
  while (Date.now() - tStart < 480000) { s = await snap(page); if (s.state === "RUN") break; await sleep(2000); }
  check(s.state === "RUN", `fight started after ${((Date.now() - tStart) / 1000).toFixed(0)}s (tiles loaded ${s.tiles.loaded})`);
  if (s.state !== "RUN") { await page.screenshot({ path: path.join(OUT, `pptr_${name.replace(/\s/g, "_")}_stuck.png`) }); await page.close(); return; }
  // Frame rate as reported by the engine (software GL here).
  await sleep(4000);
  s = await snap(page);
  console.log(`    reported fps ${s.fps} (software renderer), ships ${s.enemies}, lives ${s.lives}`);
  const rects = s.touch_buttons || {};
  const centre = (k) => [(rects[k][0] + rects[k][2] / 2) / dpr, (rects[k][1] + rects[k][3] / 2) / dpr];
  check(rects.fire && rects.rocket && rects.boost && rects.up, "touch buttons laid out");
  const [fx, fy] = centre("fire");
  await touchHold(client, fx, fy, 1200);
  s = await snap(page);
  check(s.firing === true, `FIRE button fires (tap at ${fx.toFixed(0)},${fy.toFixed(0)})`);
  await touchRelease(client);
  const before = s.rockets;
  const [rx, ry] = centre("rocket");
  await touchHold(client, rx, ry, 300); await touchRelease(client); await sleep(400);
  s = await snap(page);
  check(s.rockets < before, `ROCKET button fires a rocket (${before} -> ${s.rockets})`);
  const vw = device.viewport.height, vh = device.viewport.width; // landscape css px
  await touchDrag(client, vw * 0.3, vh * 0.5, vw * 0.3 + 110, vh * 0.5, 600);
  s = await snap(page);
  check(s.touch_axes && s.touch_axes[0] > 0.5, `drag right steers right (axes ${JSON.stringify(s.touch_axes)})`);
  await touchRelease(client);
  const [bx, by] = centre("boost");
  await touchHold(client, bx, by, 1200);
  s = await snap(page);
  check(s.telemetry && s.telemetry.boost > 0.3, `BOOST button boosts (boost ${(s.telemetry || {}).boost})`);
  await touchRelease(client);
  await page.screenshot({ path: path.join(OUT, `pptr_${name.replace(/\s/g, "_")}_fight.png`) });
  check(errors.length === 0, `no page errors (${errors.length})`);
  errors.slice(0, 5).forEach((e) => console.log("    " + e.slice(0, 200)));
  await page.close();
}

(async () => {
  const browser = await puppeteer.launch({
    executablePath: CHROME, headless: true,
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--no-sandbox", "--autoplay-policy=no-user-gesture-required"],
  });
  for (const d of DEVICES) await runDevice(browser, d.trim());
  await browser.close();
  console.log("\nRESULT " + (fails ? `FAIL (${fails})` : "PASS"));
  process.exit(fails ? 1 : 0);
})();
