#!/usr/bin/env python3
"""thor_bridge — client for the Hearthvale debug virtual-controller bridge.

Connects to the localhost TCP bridge (set up via `adb forward`) and sends
newline-delimited JSON commands. The Pi-side runner handles timing (e.g. a
`hold` keeps a stick value for N seconds, then resets) so the game protocol
stays timer-free.

Usage:
  thor_bridge.py --port 47123 ping
  thor_bridge.py --port 47123 stick right 1.0 0.0      # set the right stick
  thor_bridge.py --port 47123 hold right 1.0 0.0 2.0   # orbit right for 2 s
  thor_bridge.py --port 47123 button a true
  thor_bridge.py --port 47123 reset
  thor_bridge.py --port 47123 telemetry
"""
import argparse
import json
import socket
import sys
import time


def _send(sock, payload: dict) -> dict:
    sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
    # read one response line
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = sock.recv(4096)
        if not chunk:
            break
        buf += chunk
    line = buf.decode("utf-8").strip()
    if not line:
        return {"type": "error", "message": "empty response"}
    return json.loads(line)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=47123)
    ap.add_argument("command")
    ap.add_argument("args", nargs="*")
    args = ap.parse_args()

    cmd = args.command
    rest = args.args
    payload = None
    hold_seconds = 0.0
    post_reset = False

    if cmd == "ping":
        payload = {"cmd": "ping"}
    elif cmd == "stick":
        stick, x, y = rest[0], float(rest[1]), float(rest[2])
        payload = {"cmd": "set_stick", "stick": stick, "x": x, "y": y}
    elif cmd == "hold":
        # hold <stick> <x> <y> <seconds>  (client-side timing)
        stick, x, y, hold_seconds = rest[0], float(rest[1]), float(rest[2]), float(rest[3])
        payload = {"cmd": "set_stick", "stick": stick, "x": x, "y": y}
        post_reset = True
    elif cmd == "button":
        button, pressed = rest[0], rest[1].lower() in ("1", "true", "press", "down")
        payload = {"cmd": "button", "button": button, "pressed": pressed}
    elif cmd == "axis":
        name, value = rest[0], float(rest[1])
        payload = {"cmd": "set_axis", "axis": name, "value": value}
    elif cmd == "reset":
        payload = {"cmd": "reset_input"}
    elif cmd == "telemetry":
        payload = {"cmd": "telemetry"}
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        return 2

    try:
        sock = socket.create_connection(("127.0.0.1", args.port), timeout=5.0)
    except OSError as e:
        print(f"connect failed (run `tools/thor forward` first?): {e}", file=sys.stderr)
        return 1

    try:
        resp = _send(sock, payload)
        print(json.dumps(resp))
        if cmd == "hold":
            time.sleep(hold_seconds)
            reset_resp = _send(sock, {"cmd": "reset_input"})
            print(json.dumps(reset_resp))
    finally:
        sock.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
