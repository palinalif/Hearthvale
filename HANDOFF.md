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

---

## 2026-09-19 (later) — device state + sculpt-freeze A/B result

**Device:** `192.168.1.15:38865` (wireless ADB; the connection drops and must be
`adb connect`'d again per command batch — restart the adb server if it vanishes).
**Installed:** `org.hearthvale.game.test.m2night` **versionCode 39**
= commit `3d96e70` (task/water-river): user-approved 16-cell baseline +
`df7a095` house idle-cache + `e514b16` house roof fix. Built from worktree
`/tmp/hv-perf` with a local `export_presets.cfg` override
(`package/unique_name=org.hearthvale.game.test.m2night`, `version/code=39`;
the committed preset says `org.hearthvale.game` v5 — that naming was never
committed). One libvoxel, debug-signed. Game force-stopped after the
sanity stroke (screen returns to screensaver; stroke was undone first).
The live tree also carries the user's uncommitted water WIP — never ship
that, never edit it.

**Sculpt freeze investigation (this session, all on-device A/B,
raise-sculpt 3×4s strokes, current starter valley):**
- v37 profile (16-cell baseline): 25.3 fps / 40.0 ms avg / ~100–110 ms spikes
  at stroke end (25.0/40.5ms in an earlier session too — repeatable).
- 32-cell + GPU-generation variant (`6cdfa80`+`f6e6cc1`+`d04d743`):
  18.7 fps / 53.5 ms / 167–250 ms spikes, 2,296 draws — **worse**.
  Reverted: `3d96e70` (pushed).
- GPU generation alone (16-cell): 25.0/41.4 ms — no effect.
Conclusion: the spike is CPU work inside the voxel pipeline when sculpt
commits re-mesh edited blocks; scene-layer process stays flat (~45 ms).
Next candidate (todo #9): reduce per-edit re-mesh cost (pre-baked static
mesh for untouched terrain). The user's uncommitted water WIP may also
interact (WIP water rebuild vs native generation — open question).

---

## 2026-09-19 (late) — v40: water-freeze fix verified on device

**Installed:** `org.hearthvale.game.test.m2night` **versionCode 40** =
commit `612bec2` (task/water-river, **pushed**). Built from worktree
`/tmp/hv-waterfix` (extension copied from `/tmp/hv-perf`; local preset
override `org.hearthvale.game.test.m2night` v40). APK also stashed at
`/tmp/hearthvale-v40-waterfix-debug.apk`; worktree deletable.
Device still `192.168.1.15:38865`; game closed, screensaver restored.

**The fix** (the user's reported "water freezes for a good few seconds"): a
water region resample paid ~194 native voxel reads *per cell* (full 256-cell
column scan) and drained synchronously — the ~1,750-cell starter river
cost ~242k reads ≈ seconds, on every terrain edit near it. Now: (1) banded
probes (32-cell window around the previous top; full scan only at region
ingest) ≈ 8× fewer reads, (2) drains over 12ms/time frame once a region
passes 2048 cells, (3) the 16-cell block size stays (32-cell was worse for
sculpt — see above).

**On-device evidence (v40):** fresh load with river visible: 54.9 → 61.2
fps, no stall (v39-era baseline: multi-second freeze at load). Three
4-second river strokes (same harness as the v38/v39 sculpt A/B): max
process frame 181 ms (a single commit-time re-mesh spike, same family as
the sculpt end-of-stroke spikes), fps 4–19 during the stroke — continuous
drawing, no multi-second freeze. Strokes were undone before close.

**New observation, NOT fixed (needs a design call):** a stream stroke whose
drift travels up a steep hill draws a straight ribbon between the start and
end points — with very different terrain heights it renders as a near-
vertical white beam through the terrain (visible in the test screenshots,
undone after). Question for the user: should stream ribbons follow the
terrain height profile / clamp large elevation jumps?
