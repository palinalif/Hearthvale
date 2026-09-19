# Hearthvale — valley 15 fps cap bisection handoff

2026-09-19, branch `task/water-river` (head `f8b6da4`).
Read `AGENTS.md`, the active ticket (`tasks/M2-hamlet-building.md`) and the
user's current request. The preceding packed-earth handoff (2026-09-12) is
preserved verbatim in `reports/handoffs/HANDOFF-a85d28d.md`.

## Active work

The M2 starter valley runs at a hard **15.0 fps cap** on the AYN Thor
(min = max, 66.7 ms period — the build previously ran a throttled 24–30, so
this is a new ceiling, not thermal). Ruled out so far:

- Terrain viewer / GPU: a viewer `view_distance` sweep 64→48→32 left fps at
  15 while primitives dropped (5.09M→3.62M in that world's session).
- Display pacing: `Performance.TIME_PROCESS` ≈ **70 ms on every frame**
  (physics 0.02 ms; the scene's own phase timers < 0.5 ms) — the main
  thread is genuinely busy for the whole frame, so ~69 ms is unattributed.

Settled frame facts (current world, v20 build): 940 draws / 2.93M prims /
1023 render objects / ~467 MB static memory.

**Next:** launch v21 (`f8b6da4`, carries the `frame_clock` bridge cmd) and
read the pre / scene-chain / post main-loop split (rolling 300-frame
averages, warmup excluded). `scene_ms` dominant → bisect with
`tree_survey` / `probe_nodes`; `post_ms` dominant → render handoff / GPU
pipeline on this device.

## Device state (volatile — refresh on change)

- Thor wireless debugging: last seen `192.168.1.15`, main port `33511`.
  Ports change on reboot/sleep; Android 11+ requires re-pairing after each
  reboot — take the pairing port + 6-digit code from the Wireless-debugging
  screen, `adb pair`, then connect to the fresh main port. Stale entries
  linger as `offline` ghosts — `adb disconnect` them.
- Test package `org.hearthvale.game.test.m2night`: device had code 20;
  **v21 (`f8b6da4`) is built and verified** (one `libvoxel*` entry
  byte-identical to the pinned local copy, canonical debug keystore) and
  installed; force-stopped, not yet launched. Launcher activity is
  `org.hearthvale.game.test.m2night/com.godot.game.GodotAppLauncher`
  (verified via `resolve-activity`) — launch with `monkey -p <pkg> -c
  android.intent.category.LAUNCHER 1`; it is *not* `MainActivity`.
- In-game debug bridge: TCP 47123 (debug-gated, inert in release),
  `adb forward tcp:47123 tcp:47123`, one fresh connection per command;
  send the raw JSON command verbatim (e.g. `{"cmd":"frame_clock"}`).
- Protocol: close the game between unattended rounds and return the screen
  to the Chrome screensaver (cooling + OLED burn-in protection).

## One-off bridge diagnostics (debug builds only)

- `frame_clock` — main-loop phase brackets (pre / scene `_process` / post),
  rolling 300-frame ms averages; first call starts the sample, the next
  call reads it.
- `tree_survey` / `probe_nodes` — per-node census and per-frame-cost
  bisection.
- `mesh_survey` / `tune` — primitive census and allow-listed
  terrain/viewer A/B knobs.
- `telemetry` — fps / draws / prims / memory plus SurfaceFlinger timestats.

## Pending decisions

- Scene-chain flattening (todo #17): the 54-link gameplay scene
  inheritance chain is up for evaluation; flattening is a design-scope
  change and waits for the user's approval.
