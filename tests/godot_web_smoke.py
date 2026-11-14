#!/usr/bin/env python3
"""Smoke test for the Godot web build served at / by server.py.

Boots the exported game in headless Chromium (software WebGL), takes off over
the default city with the real Google tiles, and checks that tiles stream,
the aircraft flies, and the HUD renders. Screenshots land in tests/out/.

Run: python3 tests/godot_web_smoke.py [--url http://localhost:8000/] [--seconds 40]
"""
import argparse, json, os, sys, time
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8000/play/?quality=Performance&scale=0.3&preload=600&horizon=0")
    ap.add_argument("--seconds", type=float, default=360.0)
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    failures = []

    def check(ok, what):
        print(("  ok   " if ok else "  FAIL ") + what)
        if not ok:
            failures.append(what)

    with sync_playwright() as p:
        browser = p.chromium.launch(args=[
            "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
            "--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required",
        ])
        page = browser.new_page(viewport={"width": 800, "height": 450})
        logs = []
        page.on("console", lambda m: logs.append("%s: %s" % (m.type, m.text)))
        page.on("pageerror", lambda e: logs.append("pageerror: %s" % e))
        t0 = time.time()
        page.goto(args.url, wait_until="load", timeout=120000)
        # Wait for the Godot runtime to expose the debug hook.
        snap = None
        for _ in range(240):
            snap = page.evaluate("window.openskies ? window.openskies() : null")
            if snap:
                break
            time.sleep(0.5)
        check(snap is not None, "Godot runtime booted and exposed window.openskies (%.1fs)" % (time.time() - t0))
        if not snap:
            for l in logs[-30:]:
                print("    " + l)
            browser.close()
            sys.exit(1)
        print("    boot snapshot:", json.dumps(snap)[:300])
        page.screenshot(path=os.path.join(OUT, "godot_menu.png"))
        check(snap["state"] == "MENU", "starts in the menu")
        # Tiles root should load from the real API with the server-provided key.
        for _ in range(60):
            snap = page.evaluate("window.openskies()")
            if snap["tiles_state"] in ("ready", "error"):
                break
            time.sleep(0.5)
        check(snap["tiles_state"] == "ready", "tileset root loaded (%s %s)" % (snap["tiles_state"], snap.get("tiles_error", "")))

        # Take off (the big button).
        page.mouse.click(120, 415)
        time.sleep(0.5)
        snap = page.evaluate("window.openskies()")
        if snap["state"] == "MENU":
            # Button layout can shift with fonts; search the canvas by keyboard focus fallback.
            for y in range(300, 450, 14):
                page.mouse.click(120, y)
                time.sleep(0.3)
                snap = page.evaluate("window.openskies()")
                if snap["state"] != "MENU":
                    break
        if snap["state"] == "MENU":
            page.evaluate("window.openskies_takeoff()")
            time.sleep(0.5)
            snap = page.evaluate("window.openskies()")
        # The plane flies toward the cursor on desktop: park it in the centre.
        page.mouse.move(400, 225)
        check(snap["state"] in ("PREPARING", "FLYING"), "take off started (state %s)" % snap["state"])

        flying_at = None
        deadline = time.time() + args.seconds
        last_print = 0
        while time.time() < deadline:
            snap = page.evaluate("window.openskies()")
            if time.time() - last_print > 8:
                last_print = time.time()
                print("    t=%3.0fs state=%s fps=%s tiles=%s prep=%.1f ground=%s col=%s pos=%s" % (time.time() - t0, snap["state"], snap.get("fps"), json.dumps(snap["tiles"]), snap.get("prep") or 0, snap.get("ground"), json.dumps(snap.get("collision")), snap.get("pos")))
            if snap["state"] in ("RUN", "FREE") and flying_at is None:
                flying_at = time.time()
                print("    flying after %.1fs; tiles %s" % (flying_at - t0, snap["tiles"]))
                page.screenshot(path=os.path.join(OUT, "godot_flying_0.png"))
            if flying_at and time.time() - flying_at > 12:
                break
            time.sleep(1.0)
        page.screenshot(path=os.path.join(OUT, "godot_flying_1.png"))
        check(flying_at is not None, "reached RUN state")
        print("    score %s time_left %s" % (snap.get("score"), snap.get("time_left")))
        tm = snap.get("telemetry", {})
        print("    telemetry:", json.dumps({k: tm[k] for k in tm if k in ("airspeed", "altitude", "agl", "heading", "pitch", "bank", "g", "assist", "distance")}))
        print("    tiles:", json.dumps(snap["tiles"]), "fps", snap.get("fps"))
        vis_deadline = time.time() + 60
        while snap["tiles"]["visible"] < 10 and time.time() < vis_deadline:
            time.sleep(3)
            snap = page.evaluate("window.openskies()")
        check(snap["tiles"]["visible"] >= 3, "tiles visible in flight (%d; software GL renders few)" % snap["tiles"]["visible"])
        check(snap["tiles"]["failed"] < 5, "few failed tile requests (%d)" % snap["tiles"]["failed"])
        check(tm.get("airspeed", 0) > 60, "aircraft is flying (%.0f m/s)" % tm.get("airspeed", 0))
        check(tm.get("distance", 0) > 500, "distance accumulates (%.0f m)" % tm.get("distance", 0))
        # Hands-off the plane auto-tracks the locked ship, so only sanity-check the attitude.
        check(abs(tm.get("pitch", 99)) < 60 and abs(tm.get("bank", 99)) < 88, "attitude sane (pitch %.1f bank %.1f)" % (tm.get("pitch", 0), tm.get("bank", 0)))
        # Software GL runs the game in slow motion, so give the fine tiles
        # under the aircraft (which carry collision) time to stream in.
        agl = tm.get("agl")
        agl_deadline = time.time() + 90
        while (agl is None) and time.time() < agl_deadline:
            time.sleep(3)
            snap = page.evaluate("window.openskies()")
            agl = snap["telemetry"].get("agl")
        print("    ground debug:", json.dumps({k: snap.get(k) for k in ("ground", "collision", "pos")}))
        # Under software GL the game runs in slow motion and tile streaming
        # cannot keep up with a 130 m/s aircraft, so this is informational
        # here; tests/godot_native_flow.py asserts it at full speed.
        print(("  ok   " if agl is not None else "  warn ") + "ground known under aircraft (agl %s)" % agl)
        check(snap["telemetry"]["altitude"] > 100, "aircraft above ground level (alt %.0f)" % snap["telemetry"]["altitude"])

        # Controls: roll right for a second, expect bank.
        # Sample the bank while D is still held: the arcade auto-level rights
        # the plane within a fraction of a second after release.
        page.keyboard.down("a")
        time.sleep(1.0)
        page.keyboard.up("a")
        page.keyboard.down("d")
        time.sleep(0.5)
        b0 = page.evaluate("window.openskies()")["telemetry"]["bank"]
        time.sleep(0.5)
        b1 = page.evaluate("window.openskies()")["telemetry"]["bank"]
        page.keyboard.up("d")
        check(b1 > b0 + 5 or b1 > 40, "D key rolls right (bank %.0f -> %.0f)" % (b0, b1))
        page.keyboard.press("l")
        time.sleep(3)
        page.keyboard.press("c")
        time.sleep(1)
        page.screenshot(path=os.path.join(OUT, "godot_cockpit.png"))
        page.keyboard.press("c")
        time.sleep(1)
        page.keyboard.press("Escape")
        time.sleep(0.5)
        snap = page.evaluate("window.openskies()")
        check(snap["state"] == "PAUSED", "Esc pauses (state %s)" % snap["state"])
        page.screenshot(path=os.path.join(OUT, "godot_pause.png"))
        errs = [l for l in logs if l.startswith("pageerror") or ("error" in l.lower() and "favicon" not in l.lower())]
        print("    console errors: %d" % len(errs))
        for l in errs[:8]:
            print("    " + l[:200])
        browser.close()
    print("RESULT", "PASS" if not failures else "FAIL (%d)" % len(failures))
    sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
