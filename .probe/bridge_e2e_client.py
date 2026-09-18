#!/usr/bin/env python3
"""External-process E2E reliability test for the debug TCP bridge.

Spawns a REAL godot --headless process (.probe/bridge_e2e.tscn loads the real
scripts/m1_debug_bridge.gd under a stub game node) and drives the wire with a
plain external Python socket client — two separate processes, as required
(same-process headless loopback is known to mislead).

Reliability matrix:
  1  ping -> valid JSON pong
  2  action/state -> valid JSON
  3  clean disconnect -> immediate reconnect works
  4  abrupt close (shutdown+close, no FIN) -> reconnect works
  5  20 sequential connect->ping->disconnect cycles, no wedge
  6  malformed JSON -> error reply, connection still works after
  7  valid JSON non-object -> error reply, future connections work
  8  unknown command -> error reply, bridge stays up
  9  silent client (connects, never sends) is recycled; next client works
  10 two requests in one TCP segment -> two replies

Usage: python3 .probe/bridge_e2e_client.py
Exit code 0 = all pass.
"""
import json
import os
import signal
import socket
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT_BIN", "godot")
PORT = 47123
LOG = "/tmp/e2e_host.log"

results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))
    print(("PASS  " if ok else "FAIL  ") + name + (("  " + detail) if detail else ""), flush=True)


def connect(timeout=10.0):
    return socket.create_connection(("127.0.0.1", PORT), timeout=timeout)


def roundtrip(sock, obj=None, timeout=8.0, raw=None):
    """Send one JSON line, return parsed reply dict (None on no/short reply)."""
    sock.settimeout(timeout)
    if raw is not None:
        payload = raw
    else:
        payload = (json.dumps(obj) + "\n").encode()
    sock.sendall(payload)
    data = b""
    while b"\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    if not data:
        return None
    line = data.split(b"\n", 1)[0].decode("utf-8", "replace")
    if not line:
        return None
    try:
        return json.loads(line)
    except ValueError:
        return {"type": "error", "message": "non-json reply: " + line[:80]}


def expect(name, reply, **want):
    ok = reply is not None
    detail = json.dumps(reply) if reply is not None else "no reply"
    if ok:
        for key, val in want.items():
            if reply.get(key) != val:
                ok = False
                detail += "  (want %s=%r, got %r)" % (key, val, reply.get(key))
                break
    check(name, ok, detail)


def main():
    logf = open(LOG, "wb")
    host = subprocess.Popen(
        [GODOT, "--headless", "--path", ROOT, ".probe/bridge_e2e.tscn"],
        stdout=logf, stderr=subprocess.STDOUT, cwd=ROOT,
    )
    try:
        deadline = time.time() + 90
        ready = False
        while time.time() < deadline:
            if host.poll() is not None:
                print("HOST DIED EARLY; log:\n" + open(LOG).read(), file=sys.stderr)
                return 1
            if "E2E_HOST_READY" in open(LOG, errors="replace").read():
                ready = True
                break
            time.sleep(0.25)
        if not ready:
            print("host never reported ready; log:\n" + open(LOG, errors="replace").read(), file=sys.stderr)
            return 1
        time.sleep(0.5)  # let the listen() path settle before first connect

        # 1. ping
        s = connect()
        expect("01 ping -> pong", roundtrip(s, {"cmd": "ping"}), type="pong")
        s.close()

        # 2. action/state
        s = connect()
        expect("02 action state", roundtrip(s, {"cmd": "action", "name": "state", "args": []}),
               type="state", tool="raise")
        s.close()

        # 2b. action select_tool (semantic verb through the wire)
        s = connect()
        expect("02b action select_tool water",
               roundtrip(s, {"cmd": "action", "name": "select_tool", "args": ["water"]}),
               type="ok", tool="water")
        st = roundtrip(s, {"cmd": "action", "name": "state", "args": []})
        expect("02c state after select_tool", st, type="state", tool="water")
        roundtrip(s, {"cmd": "action", "name": "select_tool", "args": ["raise"]})
        s.close()

        # 3. clean disconnect -> immediate reconnect
        s = connect()
        expect("03a first session", roundtrip(s, {"cmd": "ping"}), type="pong")
        s.close()
        s2 = connect()
        expect("03b immediate reconnect", roundtrip(s2, {"cmd": "ping"}), type="pong")
        s2.close()

        # 4. abrupt close (no clean shutdown) -> reconnect
        s = connect()
        expect("04a abrupt session", roundtrip(s, {"cmd": "ping"}), type="pong")
        s.shutdown(socket.SHUT_RDWR)
        s.close()
        s2 = connect()
        expect("04b reconnect after abrupt close", roundtrip(s2, {"cmd": "ping"}), type="pong")
        s2.close()

        # 5. 20 sequential connect->ping->disconnect cycles
        wedged_at = None
        for i in range(20):
            try:
                c = connect(timeout=10.0)
                r = roundtrip(c, {"cmd": "ping"}, timeout=10.0)
                c.close()
                if r is None or r.get("type") != "pong":
                    wedged_at = i
                    break
            except OSError:
                wedged_at = i
                break
        check("05 20x connect->ping->disconnect cycles", wedged_at is None,
              "" if wedged_at is None else "wedged at cycle %d" % wedged_at)

        # 6. malformed JSON -> error, same connection still works
        s = connect()
        expect("06a malformed json -> error", roundtrip(s, raw=b"this is not json\n"),
               type="error")
        expect("06b same connection after bad json", roundtrip(s, {"cmd": "ping"}), type="pong")
        s.close()

        # 7. valid JSON, non-object -> error, future connections work
        s = connect()
        expect("07a json array -> error", roundtrip(s, raw=b"[1,2,3]\n"), type="error")
        s.close()
        s2 = connect()
        expect("07b reconnect after non-object json", roundtrip(s2, {"cmd": "ping"}), type="pong")
        s2.close()

        # 8. unknown command -> error, bridge stays up
        s = connect()
        expect("08a unknown cmd -> error", roundtrip(s, {"cmd": "fly_to_moon"}), type="error")
        expect("08b ping after unknown cmd", roundtrip(s, {"cmd": "ping"}), type="pong")
        s.close()

        # 9. silent client recycled by grace window; next client works
        s = connect()
        time.sleep(4.5)  # > 3s silent grace in the bridge
        s.close()
        s2 = connect()
        expect("09 reconnect after silent-client recycle", roundtrip(s2, {"cmd": "ping"}), type="pong")
        s2.close()

        # 10. two requests in one TCP segment
        s = connect()
        s.settimeout(8.0)
        s.sendall(b'{"cmd":"ping"}\n{"cmd":"ping"}\n')
        got = b""
        while got.count(b"\n") < 2:
            chunk = s.recv(4096)
            if not chunk:
                break
            got += chunk
        lines = [json.loads(l) for l in got.split(b"\n") if l]
        check("10 two requests one segment -> two pongs",
              len(lines) == 2 and all(l.get("type") == "pong" for l in lines),
              json.dumps(lines) if len(lines) <= 2 else "unexpected: %d lines" % len(lines))
        s.close()
    finally:
        host.send_signal(signal.SIGTERM)
        try:
            host.wait(timeout=10)
        except subprocess.TimeoutExpired:
            host.kill()
        logf.close()

    failed = [r for r in results if not r[1]]
    print("\n%d/%d checks passed" % (len(results) - len(failed), len(results)))
    if failed:
        print("FAILED:", [r[0] for r in failed])
        print("\n--- host log tail ---")
        tail = open(LOG, errors="replace").read().splitlines()
        print("\n".join(tail[-40:]))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
