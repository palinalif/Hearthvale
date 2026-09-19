# Hearthvale — valley 15 fps: cause found, fix pending

2026-09-19, branch `task/water-river` (head `bea51fa`).
Read `AGENTS.md`, the active ticket (`tasks/M2-hamlet-building.md`) and the
user's current request. The preceding packed-earth handoff (2026-09-12) is
preserved verbatim in `reports/handoffs/HANDOFF-a85d28d.md`.

## Diagnosis (complete)

The M2 starter valley runs at **15.0 fps** (68 ms period) on the AYN Thor.
`frame_clock` (main-loop brackets, added `119b97c`; probe-node parent fix
`cfdbcfc`) shows the split: **pre 8.0 ms / scene `_process` 46.6 ms / post
13.5 ms**. The scene cost is the whole story.

The scene `_process` cost decomposes via `last_frame_costs` + per-refresh
timers (commit `bea51fa`, all keys read live over the bridge, median of 6):

| phase | ms | what it is |
|---|---|---|
| `presentation_ms` | 47.9 | all of it, below |
| `pres_massing_shells` | **28.5** | `m2_scene_house_massing._refresh_massing_shells()` — per house, `HouseMassingVisual.show_view()` rebuilds the joined massing shell mesh **every frame, no change-detect** |
| `pres_house_landing` | 5.7 | `_refresh_house_landing()` — same pattern |
| `pres_raised_foundation` | 5.3 | `_refresh_raised_foundation_masonry()` — same pattern |
| `pres_house_accents` / `pres_facade_depth` / `pres_roof_accessories` / `pres_roof_materials` / `pres_house_shape_lbl` | ~1.7–1.9 each | one-line `_refresh_*` calls, each presumably doing per-frame dictionary walks/rebuilds |
| everything else (camera, focus, overlay, sculpt, preview, 8 more refreshes) | <0.5 total | fine |

Ruled out earlier (kept for the record): terrain viewer/GPU (view_distance
sweep 64→48→32, fps unchanged, 5.09M→3.62M prims in that world), water
visual churn (0.06 ms idle), physics (0.02 ms). Settled frame facts
(current world): 940 draws / 2.93M prims / ~467 MB static memory.

## Next: the fix (todo #8, in progress)

Add **no-change caches** to the hot refresh functions, following the
existing `_presentation_key` pattern already used by the base
`m1_scene._update_presentation()` (which is itself idle-cheap): cache keyed
per building on `(id, building_world.get_revision(), transform, dims,
material ids)`; on a hit skip the mesh/overlay rebuild entirely, but keep
per-frame items that must stay live (selection highlight, portion ghost
during placement). Target: reclaim ~40–45 ms/frame → ~35–50 fps idle.
Massing shells first (28.5 ms = 60% of the frame); landing and
raised-foundation next if the same shape applies; the 1.7–1.9 ms five only
if the first three don't already reach target.

Do not change visuals, materials or M2 behavior — this is a skip-when-
identical optimization; the user visually accepts.

## Device state (volatile — refresh on change)

- Thor wireless debugging: `192.168.1.15`, main port **33511** (verified
  this session; ports change on reboot/sleep — re-pair then connect).
  The adb daemon on the workstation drops between some command batches:
  re-`adb connect` and re-`adb forward` at the top of each batch.
- Test package `org.hearthvale.game.test.m2night` is at **versionCode 27**
  (`bea51fa` debug export, per-refresh timing build) and is the installed,
  running build. Version codes are monotonic per package — always set
  `version/code` **above** the installed one or `adb install -r` is
  rejected as a downgrade (the repo preset pins 5; bump it in a sed-copied
  `export_presets.cfg`, restore after export).
- In-game debug bridge: TCP 47123 (debug-gated, inert in release),
  `adb forward tcp:47123 tcp:47123`, **one fresh connection per command**
  (a second command on a reused connection dead-ends); read by chunk-recv
  until quiet (responses may lack a trailing newline).
- `frame_clock` — main-loop phase brackets (pre / scene / post), rolling
  ~300-frame ms averages. `telemetry` — fps/draws/prims/memory +
  SurfaceFlinger timestats **plus `last_frame_costs`** (the scene phase
  timers; includes the `pres_*` per-refresh keys while the timing build is
  installed). `mesh_survey` / `tune` / `tree_survey` / `probe_nodes` also
  available.
- Protocol: close the game between unattended rounds and return the screen
  to the Chrome screensaver (`am force-stop` then `am start -n
  com.android.chrome/...`) for cooling + burn-in protection; relaunch only
  when a fresh reading is needed.

## Gotchas hit this session (kept because each cost a build cycle)

- A `SCRIPT ERROR: Parse Error: round` at script load kills a **typed
  Dictionary function's return value** (returns `{}`), which the bridge
  forwards silently — "bridge works, all `{}`" meant a parse error in the
  probe script, not a transport problem. Godot 4.7.2's `round()` is
  single-arg; format floats with `%.3f` instead.
- The frame-clock probe was built but not added to the tree
  (`get_tree().root.add_child()` from within the scene's own `_ready()`
  fails — "root is busy"); adding it to the scene node works.
- Debug APKS here report `OS.is_debug_build() = true` on device (verified
  with a temporary startup print) — the bridge works in them.

## Pending decisions

- Scene-chain flattening (todo #17): the 54-link gameplay scene
  inheritance chain is up for evaluation; flattening is a design-scope
  change and waits for the user's approval.
