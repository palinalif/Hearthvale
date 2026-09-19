#!/usr/bin/env python3
"""One-shot performance A/B ladder for the Thor (debug bridge).

Self-healing: reconnects adb (wireless port), (re)installs the debug APK,
launches the game, waits for the bridge and for terrain meshing to settle,
then runs a ladder of `tune` A/B states and samples steady-state telemetry
after each. Writes a JSON report under .playtest/ab-ladder/<ts>/ and prints
a summary table.

Usage:
  timeout 1800 python3 tools/ab_ladder.py [--apk builds/hearthvale-m2-dx-debug-XXXX.apk]

Design notes:
- Every adb/subprocess call is timeout-bounded; every step retries with a
  backoff so a flapping wireless-debug connection is survivable.
- States are restored after each measurement so each lever is measured
  independently against the same baseline.
"""
import argparse
import glob
import json
import os
import re
import socket
import subprocess
import sys
import time

DEFAULT_ADB = "adb"
DEVICE = "192.168.1.15:33511"
BRIDGE_PORT = 47123
APK_DEFAULT = None

def sh(args, timeout=60):
    """Run a command, return (rc, stdout+stderr). Never raises on timeout."""
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        err = (e.stderr or b"").decode(errors="replace") if isinstance(e.stderr, bytes) else (e.stderr or "")
        return 124, out + err

def adb(*args, timeout=60):
    return sh([DEFAULT_ADB, "-s", DEVICE] + list(args), timeout=timeout)

def adb_connect():
    return sh([DEFAULT_ADB, "connect", DEVICE], timeout=20)

def bridge_send(obj, wait=4.0):
    s = socket.create_connection(("127.0.0.1", BRIDGE_PORT), timeout=25)
    s.sendall((json.dumps(obj) + "\n").encode())
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    time.sleep(wait)
    return json.loads(buf.decode())

def ensure_device(max_attempts=30, wait=10):
    """Reconnect adb until the wireless device is visible. Bounded."""
    for i in range(max_attempts):
        rc, out = adb("get-state", timeout=8)
        if rc == 0 and "device" in out:
            return True
        adb_connect()
        time.sleep(wait)
    return False

def install_apk(apk, max_attempts=5):
    for i in range(max_attempts):
        rc, out = adb("install", "-r", apk, timeout=240)
        if "Success" in out:
            return True
        time.sleep(5)
    return False

def launch_game(max_attempts=5):
    for i in range(max_attempts):
        rc, out = adb("shell", "am", "force-stop", "org.hearthvale.game", timeout=20)
        rc2, out2 = adb("shell", "am", "start", "-n",
                        "org.hearthvale.game/com.godot.game.GodotAppLauncher", timeout=30)
        if "Starting" in out2:
            return True
        time.sleep(5)
    return False

def wait_bridge(max_seconds=240, poll=5):
    deadline = time.time() + max_seconds
    while time.time() < deadline:
        rc, out = sh([DEFAULT_ADB, "forward", "tcp:%d" % BRIDGE_PORT, "tcp:%d" % BRIDGE_PORT], timeout=15)
        try:
            t = bridge_send({"cmd": "telemetry"}, wait=3.0)
            if "fps" in t:
                return t
        except Exception:
            pass
        time.sleep(poll)
    return None

def wait_meshing(max_seconds=180, poll=10, stable_rounds=2):
    """Poll world_stats until terrain primitives stabilize (initial mesh done)."""
    last = None
    stable = 0
    deadline = time.time() + max_seconds
    last_stats = None
    while time.time() < deadline:
        try:
            t = bridge_send({"cmd": "action", "args": "world_stats"}, wait=6.0)
            last_stats = t
            prims = t.get("terrain_primitives", t.get("primitives", None))
            if prims is not None and prims == last:
                stable += 1
                if stable >= stable_rounds:
                    return t
            else:
                stable = 0
                last = prims
        except Exception:
            stable = 0
        time.sleep(poll)
    return last_stats

def sample(label, seconds=12):
    """Sample telemetry a few times over `seconds` and return the median-ish dict."""
    reads = []
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            reads.append(bridge_send({"cmd": "telemetry"}, wait=3.5))
        except Exception:
            pass
    if not reads:
        return {"label": label, "error": "no samples"}
    def med(key):
        vals = sorted(float(r.get(key, 0) or 0) for r in reads)
        return vals[len(vals) // 2]
    out = {
        "label": label,
        "fps": round(med("fps"), 1),
        "frame_ms": round(med("frame_ms"), 1),
        "process_ms": round(med("process_ms"), 1),
        "primitives": int(med("primitives")),
        "draw_calls": int(med("draw_calls")),
        "objects": int(med("objects")),
    }
    sc = reads[-1].get("scene_costs") or {}
    out["scene_costs"] = {k: round(float(v), 2) for k, v in sc.items() if isinstance(v, (int, float))}
    return out

def tune(target, key, value, wait=10):
    return bridge_send({"cmd": "action", "args": "tune %s %s %s" % (target, key, value)}, wait=wait)

# (label, [ (target,key,value) ... ])  — states to measure; baseline restored between.
LEVERS = [
    ("A shadow_off",  [("light", "shadow_enabled", "false")]),
    ("B shadow_24m",  [("light", "directional_shadow_max_distance", "24")]),
    ("C glow_off",    [("environment", "glow_enabled", "false")]),
    ("D fog_off",     [("environment", "fog_enabled", "false")]),
    ("E plugin_noproc", [("terrain", "process_mode", "2"), ("viewer", "process_mode", "2")]),
]
BASELINE_RESTORE = [
    ("light", "shadow_enabled", "true"),
    ("light", "directional_shadow_max_distance", "150"),
    ("environment", "glow_enabled", "true"),
    ("environment", "fog_enabled", "true"),
    ("terrain", "process_mode", "1"),
    ("viewer", "process_mode", "1"),
]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", default=None)
    ap.add_argument("--seconds", type=int, default=12, help="seconds per sample")
    ap.add_argument("--skip-install", action="store_true")
    args = ap.parse_args()

    if args.apk is None and not args.skip_install:
        cands = sorted(glob.glob("builds/hearthvale-m2-dx-debug-*.apk"))
        if not cands:
            print("no builds/hearthvale-m2-dx-debug-*.apk found (use --apk)"); return 2
        args.apk = cands[-1]
    print("APK: %s" % (args.apk or "(skip)"))

    print("[1/5] ensuring adb device ...")
    if not ensure_device():
        print("FAIL: device never came up"); return 3
    if not args.skip_install:
        print("[2/5] installing ...")
        if not install_apk(args.apk):
            print("FAIL: install did not report Success"); return 4
    else:
        print("[2/5] install skipped")
    print("[3/5] launching ...")
    if not launch_game():
        print("FAIL: launch did not start"); return 5
    print("[4/5] waiting for bridge + meshing (up to ~7 min) ...")
    first = wait_bridge()
    if first is None:
        print("FAIL: bridge never answered"); return 6
    stats = wait_meshing()
    print("  settled: %s" % json.dumps(stats)[:200])

    print("[5/5] running ladder (%ss per state) ..." % args.seconds)
    report_dir = ".playtest/ab-ladder/%s" % time.strftime("%Y%m%d-%H%M%S")
    os.makedirs(report_dir, exist_ok=True)
    rows = [sample("baseline", args.seconds)]
    for label, steps in LEVERS:
        for (t, k, v) in steps:
            tune(t, k, v)
        rows.append(sample(label, args.seconds))
        for (t, k, v) in BASELINE_RESTORE:
            tune(t, k, v, wait=6)
    # combined best (only the levers that paid; refined after first look)
    tune("light", "directional_shadow_max_distance", "24")
    tune("environment", "glow_enabled", "false")
    rows.append(sample("F combined_24m_glowoff", args.seconds))
    for (t, k, v) in BASELINE_RESTORE:
        tune(t, k, v, wait=6)

    with open(report_dir + "/ladder.json", "w") as f:
        json.dump({"apk": args.apk, "stats": stats, "rows": rows}, f, indent=1)
    print("\n%-22s %6s %7s %8s %9s %7s %6s" % ("state", "fps", "frame", "proc", "prims", "dc", "objs"))
    for r in rows:
        if "error" in r:
            print("%-22s  %s" % (r["label"], r["error"]))
            continue
        print("%-22s %6.1f %7.1f %8.1f %9d %7d %6d" % (
            r["label"], r["fps"], r["frame_ms"], r["process_ms"],
            r["primitives"], r["draw_calls"], r["objects"]))
    print("scene_costs (last sample): %s" % json.dumps(rows[-1].get("scene_costs", {})))
    print("report: %s/ladder.json" % report_dir)
    return 0

if __name__ == "__main__":
    sys.exit(main())
