#!/usr/bin/env python3
"""Phone input check: with a touch-emulating landscape viewport, tap the FIRE
and ROCKET buttons where they are drawn and drag on the left to steer; verify
the game saw them. Run: python3 tests/godot_mobile_touch.py"""
import json, os, sys, time
from playwright.sync_api import sync_playwright

URL = "http://localhost:8000/play/?touch=1&quality=Performance&scale=0.35&preload=500&horizon=0"
W, H = 844, 390
fails = []


def check(ok, what):
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok:
        fails.append(what)


def touch_drag(page, x0, y0, x1, y1, steps=8, hold=0.6):
    cdp = page.context.new_cdp_session(page)
    cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": x0, "y": y0, "id": 1}]})
    for i in range(1, steps + 1):
        k = i / steps
        cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": x0 + (x1 - x0) * k, "y": y0 + (y1 - y0) * k, "id": 1}]})
        time.sleep(0.05)
    time.sleep(hold)
    snap = page.evaluate("window.openskies()")
    cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
    cdp.detach()
    return snap


def touch_hold(page, x, y, hold=0.8):
    cdp = page.context.new_cdp_session(page)
    cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": x, "y": y, "id": 2}]})
    time.sleep(hold)
    snap = page.evaluate("window.openskies()")
    cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
    cdp.detach()
    return snap


with sync_playwright() as p:
    browser = p.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
    ctx = browser.new_context(viewport={"width": W, "height": H}, device_scale_factor=2, is_mobile=True, has_touch=True)
    page = ctx.new_page()
    page.goto(URL, wait_until="load", timeout=120000)
    for _ in range(120):
        if page.evaluate("window.openskies ? window.openskies() : null"):
            break
        time.sleep(0.5)
    page.evaluate("window.openskies_takeoff()")
    snap = None
    deadline = time.time() + 420
    while time.time() < deadline:
        snap = page.evaluate("window.openskies()")
        if snap["state"] == "RUN":
            break
        time.sleep(2)
    check(snap and snap["state"] == "RUN", "reached RUN on a phone viewport (mobile=%s ui_scale=%.2f)" % (snap.get("mobile"), snap.get("ui_scale", 0)))
    check(snap.get("touch_enabled"), "touch controls enabled")
    time.sleep(3)
    # Button rectangles come from the game in window pixels; Playwright taps in CSS pixels.
    dpr = float(snap.get("dpr") or 1.0)
    rects = snap.get("touch_buttons", {})
    def centre(action):
        r = rects[action]
        return ((r[0] + r[2] / 2) / dpr, (r[1] + r[3] / 2) / dpr)
    check("fire" in rects and "rocket" in rects, "button layout reported (%s)" % sorted(rects.keys()))
    fx, fy = centre("fire")
    snap = touch_hold(page, fx, fy, 1.0)
    print("    touch debug:", json.dumps(snap.get("touch_debug")), "touch_fire", snap.get("touch_fire"), "ctrl_fire", snap.get("ctrl_fire"), "state", snap.get("state"), "firing", snap.get("firing"))
    check(snap.get("firing"), "FIRE button fires the guns (tapped at %.0f,%.0f css px)" % (fx, fy))
    rockets_before = snap.get("rockets")
    rx, ry = centre("rocket")
    snap = touch_hold(page, rx, ry, 0.4)
    time.sleep(0.3)
    snap = page.evaluate("window.openskies()")
    check(snap.get("rockets", 9) < rockets_before, "ROCKET button fires a rocket (%s -> %s)" % (rockets_before, snap.get("rockets")))
    # Drag on the left to steer right.
    snap = touch_drag(page, W * 0.25, H * 0.5, W * 0.25 + 120, H * 0.5)
    ax = snap.get("touch_axes", [0, 0])
    check(ax[0] > 0.5, "drag right steers right (axes %s)" % ax)
    time.sleep(0.5)
    snap = touch_drag(page, W * 0.25, H * 0.5, W * 0.25, H * 0.5 - 120)
    ax = snap.get("touch_axes", [0, 0])
    check(ax[1] > 0.5, "drag up pitches up (axes %s)" % ax)
    page.screenshot(path=os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "mobile_touch.png"), timeout=180000)
    browser.close()
print("RESULT", "PASS" if not fails else "FAIL (%d)" % len(fails))
sys.exit(0 if not fails else 1)
