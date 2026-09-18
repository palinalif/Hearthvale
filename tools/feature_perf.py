#!/usr/bin/env python3
"""feature_perf — generic on-device feature performance/interaction test.

One reusable driver + a small **spec file** per feature. The spec describes the
input sequence (via the virtual-controller bridge) and how many times to
repeat it; the driver runs it, samples in-game telemetry + SurfaceFlinger
timestats, and writes a report. Adding a new feature test = write a new spec
JSON, no code changes.

Why the bridge (not `adb shell input keyevent`)?
  The Thor runs the game on a secondary display whose input focus is shared
  with a launcher/cast window, so synthetic key events land on the wrong
  window. The bridge injects virtual *joypad* events straight into the Godot
  InputMap, which is focus-independent and indistinguishable from physical
  controller input.

Pre-reqs:
  * the debug build is installed (the bridge is OS.is_debug_build()-gated)
  * `tools/thor forward` has run (adb forward tcp:47123 -> device)
  * THOR_DEVICE set (or `adb devices` has exactly one device)

Usage:
  tools/feature_perf.py tools/specs/water-stream.json
  tools/feature_perf.py tools/specs/water-stream.json --repeat 5 --stroke-seconds 3.0
  tools/feature_perf.py tools/specs/water-stream.json --out /tmp/water-perf

The bridge protocol (newline-delimited JSON, loopback only):
  {"cmd":"ping"}                                  -> {"type":"pong"}
  {"cmd":"set_stick","stick":"right","x":1,"y":0} -> {"type":"ok"}
  {"cmd":"button","button":"a","pressed":true}    -> {"type":"ok"}
  {"cmd":"reset_input"}                           -> {"type":"ok","reset":true}
  {"cmd":"telemetry"}                             -> {"type":"telemetry",...}

Spec format (see tools/specs/*.json for examples):
  {
    "name": "water-stream",
    "description": "...",
    "repeat": 3,              # how many times to run the "stroke" sequence
    "stroke_seconds": 4.0,    # duration of each stick_drift step
    "rest_seconds": 1.5,      # rest between repeats (commit + settle)
    "setup": [ ...steps... ], # run once before the loop
    "stroke": [ ...steps... ] # run `repeat` times
  }

Step actions:
  {"do":"button", "button":"a", "pressed":true}      # press/release a joypad button
  {"do":"stick",  "stick":"right", "x":0.35, "y":0.35}  # set a stick
  {"do":"stick_drift","stick":"right","x":0.35,"y":0.35}  # drift for stroke_seconds
  {"do":"cycle",  "button":"dpad_right", "times":5}   # press a button N times (tool cycle)
  {"do":"call",   "name":"select_tool", "args":["water"]}  # semantic scene verb (debug_test_action)
  {"do":"state",  "label":"after_setup"}                  # fetch scene state into the report

Semantic verbs: state | select_tool [tool] | view_context [terrain|building]
| cancel | undo | redo. They call the same handler functions the real input
uses; strokes stay real InputMap events (button a + stick).
  {"do":"sleep",  "seconds":1.0}
  {"do":"reset"}                                   # clear virtual input
  {"do":"telemetry","label":"pre_stroke"}          # sample telemetry (label optional)
"""
import argparse
import json
import os
import socket
import subprocess
import sys
import time


# --- bridge client -----------------------------------------------------------

def _send(sock, payload: dict) -> dict:
    sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = sock.recv(4096)
        if not chunk:
            break
        buf += chunk
    line = buf.decode("utf-8").strip()
    return json.loads(line) if line else {"type": "error", "message": "empty response"}


def _connect(port: int) -> socket.socket:
    return socket.create_connection(("127.0.0.1", port), timeout=5.0)


# --- adb helpers -------------------------------------------------------------

def _adb(*args: str) -> str:
    cmd = ["adb"]
    dev = os.environ.get("THOR_DEVICE", "")
    if dev:
        cmd += ["-s", dev]
    cmd += list(args)
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def _sf_timestats(action: str) -> str:
    if action == "enable":
        return _adb("shell", "dumpsys", "SurfaceFlinger", "--timestats", "-clear", "-enable")
    if action == "dump":
        return _adb("shell", "dumpsys", "SurfaceFlinger", "--timestats", "-dump")
    if action == "disable":
        return _adb("shell", "dumpsys", "SurfaceFlinger", "--timestats", "-disable")
    raise ValueError(action)


# --- step executor -----------------------------------------------------------

def _run_step(sock, step: dict, stroke_seconds: float, samples: list) -> None:
    do = step.get("do", "")
    if do == "button":
        _send(sock, {"cmd": "button", "button": step["button"], "pressed": bool(step.get("pressed", True))})
    elif do == "stick":
        _send(sock, {"cmd": "set_stick", "stick": step.get("stick", "right"), "x": float(step.get("x", 0)), "y": float(step.get("y", 0))})
    elif do == "stick_drift":
        x = float(step.get("x", 0.35)); y = float(step.get("y", 0.35))
        stick = step.get("stick", "right")
        t0 = time.time()
        while time.time() - t0 < stroke_seconds:
            _send(sock, {"cmd": "set_stick", "stick": stick, "x": x, "y": y})
            time.sleep(0.04)
    elif do == "cycle":
        for _ in range(int(step.get("times", 1))):
            _send(sock, {"cmd": "button", "button": step.get("button", "dpad_right"), "pressed": True})
            time.sleep(0.08)
            _send(sock, {"cmd": "button", "button": step.get("button", "dpad_right"), "pressed": False})
            time.sleep(0.18)
        _send(sock, {"cmd": "reset_input"})
    elif do == "sleep":
        time.sleep(float(step.get("seconds", 0.0)))
    elif do == "reset":
        _send(sock, {"cmd": "reset_input"})
    elif do == "telemetry":
        samples.append({"phase": step.get("label", "telemetry"), **_send(sock, {"cmd": "telemetry"})})
    elif do == "call":
        resp = _send(sock, {"cmd": "action", "name": step.get("name", ""), "args": step.get("args", [])})
        if resp.get("type") == "error":
            print(f"  [warn] call {step.get('name')!r} -> {resp.get('message')}", file=sys.stderr)
    elif do == "state":
        resp = _send(sock, {"cmd": "action", "name": "state", "args": []})
        samples.append({"phase": step.get("label", "state"), **resp})
    else:
        print(f"  [warn] unknown step do={do!r}", file=sys.stderr)


def _run_steps(sock, steps: list, stroke_seconds: float, samples: list) -> None:
    for step in steps:
        _run_step(sock, step, stroke_seconds, samples)


# --- timestats parsing -------------------------------------------------------

def _is_num(s: str) -> bool:
    try:
        float(s)
        return True
    except ValueError:
        return False


def _parse_timestats(text: str) -> dict:
    """Extract the game surface's frame-interval stats (min/avg/max ms)."""
    best: dict = {}
    for line in text.splitlines():
        if "org.hearthvale" not in line and "Surface" not in line:
            continue
        nums = [float(x) for x in line.replace(",", " ").split() if _is_num(x)]
        if not nums:
            continue
        cand = {"min_ms": min(nums), "avg_ms": sum(nums) / len(nums), "max_ms": max(nums), "line": line.strip()}
        if len(nums) > len(best.get("nums", [])):
            best = {**cand, "nums": nums}
    return best


# --- main --------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spec", help="path to the spec JSON (e.g. tools/specs/water-stream.json)")
    ap.add_argument("--port", type=int, default=47123)
    ap.add_argument("--repeat", type=int, default=None, help="override spec repeat count")
    ap.add_argument("--stroke-seconds", type=float, default=None, help="override spec stroke_seconds")
    ap.add_argument("--out", default=None, help="output dir (default: .playtest/feature-perf/<name>)")
    args = ap.parse_args()

    with open(args.spec) as f:
        spec = json.load(f)

    name = spec.get("name", os.path.basename(args.spec).rsplit(".", 1)[0])
    repeat = args.repeat if args.repeat is not None else int(spec.get("repeat", 3))
    stroke_seconds = args.stroke_seconds if args.stroke_seconds is not None else float(spec.get("stroke_seconds", 4.0))
    rest_seconds = float(spec.get("rest_seconds", 1.5))
    setup = spec.get("setup", [])
    stroke = spec.get("stroke", [])
    out = args.out or f".playtest/feature-perf/{name}"

    os.makedirs(out, exist_ok=True)
    ts = time.strftime("%H%M%S")
    sf_path = f"{out}/surfaceflinger-{ts}.txt"
    tel_path = f"{out}/telemetry-{ts}.json"
    rpt_path = f"{out}/report-{ts}.txt"

    print(f"[feature-perf] spec={name} repeat={repeat} stroke_s={stroke_seconds} rest_s={rest_seconds}")
    print(f"[feature-perf] {spec.get('description', '')}")

    try:
        sock = _connect(args.port)
    except OSError as e:
        print(f"[feature-perf] bridge connect failed: {e}\n  (run `tools/thor forward` first)", file=sys.stderr)
        return 1

    pong = _send(sock, {"cmd": "ping"})
    print(f"[feature-perf] ping -> {pong}")
    if pong.get("type") != "pong":
        print("[feature-perf] bridge not responding", file=sys.stderr)
        return 1

    samples: list[dict] = []
    print("[feature-perf] enabling SurfaceFlinger timestats...")
    _sf_timestats("enable")

    try:
        print(f"[feature-perf] setup ({len(setup)} steps)...")
        _run_steps(sock, setup, stroke_seconds, samples)
        time.sleep(1.0)
        samples.append({"phase": "setup_done", **_send(sock, {"cmd": "telemetry"})})

        for i in range(repeat):
            print(f"[feature-perf] repeat {i + 1}/{repeat}...")
            _run_steps(sock, stroke, stroke_seconds, samples)
            time.sleep(rest_seconds)

        samples.append({"phase": "final", **_send(sock, {"cmd": "telemetry"})})
    finally:
        print("[feature-perf] dumping + disabling timestats...")
        with open(sf_path, "w") as f:
            f.write(_sf_timestats("dump"))
        _sf_timestats("disable")
        sock.close()

    with open(tel_path, "w") as f:
        json.dump({"spec": name, "samples": samples}, f, indent=2)

    _write_report(name, spec.get("description", ""), samples, sf_path, rpt_path)
    print(f"[feature-perf] telemetry: {tel_path}")
    print(f"[feature-perf] timestats: {sf_path}")
    print(f"[feature-perf] report:    {rpt_path}")
    return 0


def _write_report(name: str, desc: str, samples: list, sf_path: str, rpt_path: str) -> None:
    L = [f"=== Hearthvale feature-perf report: {name} ==="]
    L.append(f"generated: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    L.append(f"description: {desc}")
    L.append("")
    L.append("--- in-game telemetry (per phase) ---")
    for s in samples:
        L.append(
            f"  {s['phase']:>14}: fps={s.get('fps', 0):5.1f}  frame_ms={s.get('frame_ms', 0):6.2f}  "
            f"process_ms={s.get('process_ms', 0):6.2f}  draw={s.get('draw_calls', 0):5d}  "
            f"prims={s.get('primitives', 0):7d}  mem={s.get('memory_static_mb', 0):5.0f}MB"
        )
    fps = [s["fps"] for s in samples if s.get("fps", 0) > 1]
    proc = [s["process_ms"] for s in samples if s.get("process_ms", 0) > 0]
    if fps:
        L.append("")
        L.append(f"  avg fps={sum(fps) / len(fps):.1f}   min fps={min(fps):.1f}")
        L.append(f"  avg process_ms={sum(proc) / len(proc):.2f}   max process_ms={max(proc):.2f}")
    L.append("")
    L.append(f"--- SurfaceFlinger timestats: {os.path.basename(sf_path)} ---")
    with open(sf_path) as f:
        sf = f.read()
    parsed = _parse_timestats(sf)
    if parsed:
        L.append(f"  {parsed['min_ms']:.2f} / {parsed['avg_ms']:.2f} / {parsed['max_ms']:.2f} ms (min/avg/max)")
        L.append(f"  (raw: {sf_path})")
    else:
        L.append(f"  (no app-surface line parsed; inspect {sf_path} directly)")
    with open(rpt_path, "w") as f:
        f.write("\n".join(L) + "\n")
    print("\n".join(L))


if __name__ == "__main__":
    sys.exit(main())
