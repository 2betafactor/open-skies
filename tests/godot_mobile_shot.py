#!/usr/bin/env python3
"""Screenshots of the Godot build at phone sizes with touch controls on.
Run: python3 tests/godot_mobile_shot.py  (writes tests/out/mobile_*.png)"""
import json, os, sys, time
from playwright.sync_api import sync_playwright

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
BASE = "http://localhost:8000/play/?touch=1&quality=Performance&scale=0.35&preload=500"

with sync_playwright() as p:
    browser = p.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
    for name, w, h in [("portrait", 390, 844), ("landscape", 844, 390)]:
        ctx = browser.new_context(viewport={"width": w, "height": h}, device_scale_factor=2, is_mobile=True, has_touch=True)
        page = ctx.new_page()
        page.goto(BASE, wait_until="load", timeout=120000)
        for _ in range(120):
            if page.evaluate("window.openskies ? window.openskies() : null"):
                break
            time.sleep(0.5)
        time.sleep(2)
        page.screenshot(path=os.path.join(OUT, "mobile_%s_menu.png" % name))
        page.evaluate("window.openskies_takeoff()")
        deadline = time.time() + 400
        snap = None
        while time.time() < deadline:
            snap = page.evaluate("window.openskies()")
            if snap["state"] in ("RUN", "FREE"):
                break
            time.sleep(2)
        time.sleep(6)
        page.screenshot(path=os.path.join(OUT, "mobile_%s_flight.png" % name))
        print(name, "state", snap["state"] if snap else None, "tiles", snap["tiles"]["visible"] if snap else None)
        ctx.close()
    browser.close()
