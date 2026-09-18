#!/usr/bin/env python3
"""water_perf_test — reusable on-Heathvale water-tool performance test.

Drives the water tool through the virtual-controller bridge (the same
Godot InputMap path a physical controller uses, so it exercises the real
gameplay path), paints a deterministic set of stream strokes, and captures:

  * in-game telemetry (fps, process ms, draw calls, primitives, mem) via the bridge
  * SurfaceFlinger timestats (the actual on-device frame intervals)
  * the in-game debug overlay (the scene prints FPS/process ms/draws to a label)

Why the bridge (not `adb shell input keyevent`)?
  The Thor runs the game on a secondary display whose input focus is shared
  with a launcher/cast window, so synthetic key events land on the wrong
  window. The bridge injects virtual *joypad* events straight into the
  InputMap, which is timer-free, focus-independent, and indistinguishable
  from physical controller input.

Pre-reqs:
  * the debug build is installed (the bridge is OS.is_debug_build()-gated)
  * `tools/thor forward` has run (adb forward tcp:47123 -> device)
  * THOR_DEVICE set (or `adb devices` has exactly one device)

Usage:
  tools/water_perf_test.py --strokes 3 --stroke-seconds 4.0
  tools/water_perf_test.py --strokes 4 --stroke-seconds 3.0 --cycles 5 --out .playtest/water-perf

The `--cycles` value is the number of D-pad-right presses to reach the water
tool from the default (raise). TERRAIN_TOOLS =
  ["raise","dig","smooth","level","slope","water","foliage","tree"]  -> water is index 5.
"""
import argparse
import json
import os
import socket
import subprocess
import sys
import time


# --- bridge client (mirrors tools/thor_bridge.py) ---------------------------

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


def _btn(sock, button: str, pressed: bool) -> None:
    _send(sock, {"cmd": "button", "button": button, "pressed": pressed})


def _stick(sock, stick: str, x: float, y: float) -> None:
    _send(sock, {"cmd": "set_stick", "stick": stick, "x": x, "y": y})


def _reset(sock) -> None:
    _send(sock, {"cmd": "reset_input"})


def _telemetry(sock) -> dict:
    return _send(sock, {"cmd": "telemetry"})


# --- adb helpers (resolve the device once) ----------------------------------

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


# --- the test body ----------------------------------------------------------

def _select_water(sock, cycles: int) -> None:
    """Cycle D-pad-right `cycles` times to reach the water tool from raise."""
    for i in range(cycles):
        _btn(sock, "dpad_right", True)
        time.sleep(0.08)
        _btn(sock, "dpad_right", False)
        time.sleep(0.18)
    _reset(sock)


def _paint_stream(sock, stroke_seconds: float, samples: list, label: str) -> None:
    """Hold A + drift the right stick in a gentle diagonal to draw a stream centreline,
    then release A to commit. Samples telemetry before and after."""
    samples.append({"phase": label, "t": time.time(), **_telemetry(sock)})
    # begin the stream
    _btn(sock, "a", True)
    time.sleep(0.35)
    # drift the stick (diagonal, gentle) to lay down the centreline
    t0 = time.time()
    while time.time() - t0 < stroke_seconds:
        _stick(sock, "right", 0.35, 0.35)  # consistent diagonal drift
        time.sleep(0.04)
    # commit
    _stick(sock, "right", 0.0, 0.0)
    _btn(sock, "a", False)
    time.sleep(0.6)  # let the commit (excavation + incremental water sync) settle
    samples.append({"phase": label + "_post", "t": time.time(), **_telemetry(sock)})
    _reset(sock)


def _parse_timestats(text: str) -> dict:
    """Extract the game surface's frame-interval stats from the timestats dump.

    The dump is per-window; we want the app surface (the largest / SurfaceView /
    the 'org.hearthvale' layer). Returns a small dict of min/avg/max frame ms.
    """
    best: dict = {}
    for line in text.splitlines():
        if "org.hearthvale" not in line and "SurfaceView" not in line and "Surface" not in line:
            continue
        # timestats lines look like:
        #   <surface>  min=.. avg=.. max=..  (varies by Android version)
        nums = [float(x) for x in line.replace(",", " ").split() if _is_num(x)]
        if not nums:
            continue
        cand = {"min_ms": min(nums), "avg_ms": sum(nums) / len(nums), "max_ms": max(nums), "line": line.strip()}
        # keep the one with the most data / the app surface
        if len(nums) > len(best.get("nums", [])):
            best = {**cand, "nums": nums}
    return best


def _is_num(s: str) -> bool:
    try:
        float(s)
        return True
    except ValueError:
        return False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=47123)
    ap.add_argument("--strokes", type=int, default=3, help="number of water stream strokes")
    ap.add_argument("--stroke-seconds", type=float, default=4.0, help="duration of each stroke (A held)")
    ap.add_argument("--rest-seconds", type=float, default=1.5, help="rest between strokes (commit + settle)")
    ap.add_argument("--cycles", type=int, default=5, help="D-pad-right presses to reach water from raise")
    ap.add_argument("--out", default=".playtest/water-perf", help="output dir")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    ts = time.strftime("%H%M%S")
    sf_path = f"{args.out}/surfaceflinger-{ts}.txt"
    tel_path = f"{args.out}/telemetry-{ts}.json"
    rpt_path = f"{args.out}/report-{ts}.txt"

    print(f"[water-perf] port={args.port} strokes={args.strokes} stroke_s={args.stroke_seconds} cycles={args.cycles}")

    try:
        sock = _connect(args.port)
    except OSError as e:
        print(f"[water-perf] bridge connect failed: {e}\n  (run `tools/thor forward` first)", file=sys.stderr)
        return 1

    pong = _send(sock, {"cmd": "ping"})
    print(f"[water-perf] ping -> {pong}")
    if pong.get("type") != "pong":
        print("[water-perf] bridge not responding", file=sys.stderr)
        return 1

    samples: list[dict] = []
    print("[water-perf] enabling SurfaceFlinger timestats...")
    _sf_timestats("enable")

    try:
        print(f"[water-perf] selecting water tool ({args.cycles}x D-pad-right)...")
        _select_water(sock, args.cycles)
        time.sleep(1.0)  # let the placement preview settle
        samples.append({"phase": "water_selected", **_telemetry(sock)})

        for i in range(args.strokes):
            print(f"[water-perf] stroke {i + 1}/{args.strokes} ({args.stroke_seconds}s)...")
            _paint_stream(sock, args.stroke_seconds, samples, f"stroke{i + 1}")
            time.sleep(args.rest_seconds)

        samples.append({"phase": "final", **_telemetry(sock)})
    finally:
        print("[water-perf] dumping + disabling timestats...")
        with open(sf_path, "w") as f:
            f.write(_sf_timestats("dump"))
        _sf_timestats("disable")
        sock.close()

    with open(tel_path, "w") as f:
        json.dump(samples, f, indent=2)

    _write_report(samples, sf_path, rpt_path)
    print(f"[water-perf] telemetry: {tel_path}")
    print(f"[water-perf] timestats: {sf_path}")
    print(f"[water-perf] report:    {rpt_path}")
    return 0


def _write_report(samples: list[dict], sf_path: str, rpt_path: str) -> None:
    L = ["=== Hearthvale water-tool performance report ==="]
    L.append(f"generated: {time.strftime('%Y-%m-%d %H:%M:%S')}")
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
