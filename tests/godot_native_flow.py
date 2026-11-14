#!/usr/bin/env python3
"""Full-flow check of the Godot game, headless and native (no rendering):
menu -> take off over San Francisco -> streamed tiles -> flying with the
ground known under the aircraft. Needs the server on :8000 and network.

Run: python3 tests/godot_native_flow.py [--godot PATH] [--seconds 30]
"""
import argparse, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.environ.get("GODOT", os.path.expanduser("~/godot/Godot_v4.7.2-stable_linux.x86_64")))
    ap.add_argument("--server", default="http://localhost:8000")
    ap.add_argument("--seconds", type=int, default=45)
    args = ap.parse_args()
    cmd = [args.godot, "--headless", "--path", os.path.join(ROOT, "godot"), "--",
           "--server=" + args.server, "--autostart=1", "--trace=1", "--seconds=%d" % args.seconds, "--autofire=1", "--testkill=1", "--preload=800"]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=args.seconds * 4 + 60).stdout
    lines = [l for l in out.splitlines() if l.startswith("[trace] state=")]
    for l in lines:
        print("   ", l[:160])
    fails = 0

    def check(ok, what):
        nonlocal fails
        print(("  ok   " if ok else "  FAIL ") + what)
        fails += 0 if ok else 1

    last = lines[-1] if lines else ""
    m = lambda key: re.search(key + r"=([-\d.a-z]+)", last)
    check(bool(lines), "trace produced output")
    check("state=RUN" in last, "reached RUN (timed arcade run)")
    sc = re.search(r"score=(\d+)", last)
    kl = re.search(r"kills=(\d+)", last)
    print("    score at end:", sc.group(1) if sc else "?", "kills:", kl.group(1) if kl else "?")
    check(kl is not None and int(kl.group(1)) > 0, "guns destroyed the target ship ahead")
    vis = int(m("vis").group(1)) if m("vis") else 0
    check(vis > 15, "tiles visible (%d)" % vis)
    nfail = int(m("fail").group(1)) if m("fail") else 99
    nload = int(m("loaded").group(1)) if m("loaded") else 0
    check(nfail <= max(2, nload // 100), "few failed tile requests (%d of %d loaded)" % (nfail, nload))
    agl = m("agl").group(1) if m("agl") else "nan"
    check(agl != "nan" and float(agl) > 100, "ground known under aircraft, safe height (agl %s)" % agl)
    spd = float(m("spd").group(1)) if m("spd") else 0
    check(spd > 80, "flying (%.0f m/s)" % spd)
    errs = [l for l in out.splitlines() if "SCRIPT ERROR" in l or l.startswith("ERROR")]
    check(not errs, "no script errors (%d)" % len(errs))
    for e in errs[:5]:
        print("    " + e[:200])
    print("RESULT", "PASS" if fails == 0 else "FAIL (%d)" % fails)
    sys.exit(0 if fails == 0 else 1)


if __name__ == "__main__":
    main()
