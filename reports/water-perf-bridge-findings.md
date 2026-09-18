# On-device water-perf test — blocked-input findings (2026-09-18)

Follow-up to the "on-device water-perf test, input-injection blocked" handoff
(`task/water-river` @ `5f78648`). Both blockers are now root-caused and fixed
locally; device re-verification is pending a fresh wireless-ADB `IP:port`.

## Finding 1 — bridge `socket()` failure: missing `INTERNET` permission (fixed)

**Symptom.** `VirtualControllerBridge: listen N failed (Can't create)` for every
port and every host (127.0.0.1 and wildcard) on the Thor, while the identical
`TCPServer.listen()` succeeds headless on desktop. Seccomp=0, SELinux
permissive, 32768 FD limit / 6 open — none relevant.

**Root cause.** `export_presets.cfg` had `permissions/internet=false` on both
Android presets. Android requires the `INTERNET` permission for **any**
`socket()`/`listen()`, including loopback binds. A denied `socket()` fails with
EACCES, which Godot surfaces as "Can't create". This explains all ports, all
hosts, and the desktop-vs-device split (desktop has no such permission model).

**Fix.** `permissions/internet=true` on both Android presets
(`Android ARM64`, `Android ARM64 Compatibility`). Inert for the offline release
app: the bridge code is `OS.is_debug_build()`-gated, so release/CI never runs
it — the manifest declaration is the only release-visible change.

**Cleanup.** Reverted the uncommitted multi-port / all-interfaces probe in
`scripts/m1_debug_bridge.gd` (leftover from the blocked investigation);
loopback-only `127.0.0.1:47123` is correct again.

**Verification done.** Debug test APK rebuilt: `builds/hearthvale-grass-test.apk`
(39.8 MB, signed, package `org.hearthvale.game.testgrass`); `aapt dump
permissions` confirms `uses-permission: android.permission.INTERNET`.
On-device confirmation (logcat line `VirtualControllerBridge: listening on
port 47123`) is the remaining check — needs the device.

## Finding 2 — `input keyevent` never cycled the tool: wrong key binding (documented)

**Symptom.** `adb shell input keyevent 217` (BRIGHTNESS_UP — a misread) and then
22 (`KEYCODE_DPAD_RIGHT`) left the HUD on **Raise** even though events reached
the game.

**Root cause.** `scripts/m1_scene.gd` `_setup_input_map()`:
`m1_cycle_right` is bound to **joypad `JOY_BUTTON_DPAD_RIGHT`** + keyboard
**`KEY_BRACKETRIGHT`** (and `m1_cycle_left` to `JOY_BUTTON_DPAD_LEFT` +
`KEY_BRACKETLEFT`). Android `input keyevent` produces `InputEventKey` events,
so `KEY_DPAD_RIGHT` (22) matches no binding. The keyboard bindings are the
literal `[` / `]` keys — Android keycodes **71 / 72**.

**Working keyevent fallback (if ever needed).**
- Cycle tool right 5× to reach Water: `input keyevent 72` ×5
  (`TERRAIN_TOOLS = [raise, dig, smooth, level, slope, water, foliage, tree]`)
- Cycle left: `input keyevent 71`
- `m1_accept` (stroke start/commit) = ENTER, keycode **66**
- Orbit/aim keys = arrows (21–24); stroke = hold 66 while moving aim.
- Caveat: on Android 11 (Thor) `input keyevent` offers no true long-hold beyond
  `--longPress` (~500 ms), so a sustained stream stroke via keyevents is
  awkward — the bridge is the intended path.

## Not committed yet

- `export_presets.cfg` (internet=true) and `AGENTS.md` (both gotchas
  documented in the "On-device feature performance testing" section) are
  modified in the working tree. Commit + push + verified-APK gate run once the
  device run is green (the permission change affects the CI release manifest,
  so the gated Drive/verification workflow should validate the new head).

## Semantic verb layer (replaces keyevent emulation as the spec language)

Per user direction, specs no longer emulate key bindings. The bridge gained a
`cmd:"action"` command forwarding to a debug-gated `debug_test_action()` on the
scene (`m1_scene.gd`); the spec driver gained `call` / `state` steps:

- Verbs: `select_tool [tool]` (calls the *same* `_select_terrain_tool` the
  D-pad cycle uses — virtual dispatch to the chain tip, so the water override
  runs), `state`, `view_context [terrain|building]`, `cancel`, `undo`, `redo`.
- **Strokes remain real InputMap events** (`button a` + `stick`): the exact
  player path (`_input` → `_start_water_stream` / `_commit_water_stream`) is
  exercised, not bypassed. Tool selection is the only thing that's a direct
  call, because it's UI plumbing, and it removes the fragile 5×-cycle.
- `tools/specs/water-stream.json` now: `call select_tool water` → real
  press-A + right-stick drift → release-A, with `state` evidence samples.
- New test `tests/debug_bridge_action_test.gd` (15 checks, green): verb
  semantics + bridge JSON protocol dispatch. Registered in `tools/check.ps1`
  (`debug-bridge-action`). Bridge `_handle_command` now *returns* the reply
  dict (socket layer sends it) so the protocol is testable headless —
  same-process headless TCP peers are unreliable (status stuck CONNECTING,
  client→server bytes dropped; reproduced with zero game code). The wire is
  verified on device by the feature-perf run.
- `m1_attachment_placement_test` (full-scene regression) re-run green: 31/31.

## Remaining device steps (blocked only on `IP:port`)

1. Wireless ADB connect (port changes every reconnect — ask the user).
2. Install `builds/hearthvale-grass-test.apk`, launch, confirm in logcat:
   `VirtualControllerBridge: listening on port 47123`.
3. `tools/thor forward` → `python3 tools/feature_perf.py
   tools/specs/water-stream.json --repeat 3 --stroke-seconds 4.0
   --out .playtest/water-perf` (SurfaceFlinger timestats + in-game telemetry).
4. Before/after screenshot of one stream stroke (proves the water path
   end-to-end on device).
5. Fresh grass anisotropy (8× AF) capture alongside the run.
6. Commit/push the two config+doc changes; verify the gated CI run.
