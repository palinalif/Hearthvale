# Hearthvale — startup readiness work (2026-09-23)

**Branch:** `codex/startup-readiness`, based on `codex/terrain-moire-fix`.
The M2 backend-ready callback now completes inherited player restoration;
previously `_player_restored` stayed false and the production capture waited for
its full timeout despite terrain being ready. Fresh starter creation skips the
throwaway M1 landscape, avoids a duplicate path visual rebuild, reuses painted
path cells for planting clearance, and batches meadow tuft regeneration until
the river and ponds are established. The river's exact 25,868-cell footprint is
rasterized by collecting brush and segment cells before sorting once; its SHA256
is unchanged (`425437cb663f553a5bcc6d7fa2b89f1d0088dae29079e1bbf67489087edb12ce`).

**Desktop evidence:** Forward Mobile production cold start reached restored
readiness in 9.2–11.4 s on this host, versus 90–98.5 s before the river
rasterization fix. The standalone premade-river footprint fell from 49.9 s to
1.7 s with identical output. Headless M2 starter readiness was 34.5 s, versus
54.3–55.7 s baseline; renderer and machine load differ, so these are local
measurements rather than Thor performance claims. The complete Forward Mobile
capture passed with seven images, a native border edit, and zero failures.
Tracked reference captures were restored after the run; the latest untracked
normal image is `.tools/startup-normal-mobile.png`.

**Tests:** Godot 4.7.2: water region 55 checks, painted path region 22,
meadow tuft visual 13, M2 starter scene 26, starter valley, starter migration,
and Forward Mobile starter render all passed. The older M1 landscape test
failed twice at its fixed 30 s native-scene-ready deadline, once in parallel
and once alone; no script error was reported. Its readiness timeout needs
separate review before treating it as a regression.

**Delivery limit:** Android preset remains v69. This host still has no Java
SDK or Android build-tools/apksigner; no APK was built or verified. The Thor
was not connected, so device startup and visual approval remain untested.

# Hearthvale — terrain diagonal moiré fix branch (2026-09-22)

**Branch:** `codex/terrain-moire-fix`, source commit `d102c54` (v69 Android preset).
The grass shader's value-noise lattice hashed different values for the same
corner when adjacent cells met. That created visible square seams, which read as
diagonal bands across the terrain in perspective. All four corner samples now
use one salted lattice coordinate, so adjoining cells share each edge value.
Native terrain geometry, saves, sculpting, and grass palette parameters are
unchanged. Repaired the existing `grass_tone_test.gd` reference to the shader's
current owner (`GroundMaterials`), which had caused a parse error.

**Verification:** pinned Godot 4.7.2 headless grass-tone test: 27 checks,
0 failures. Isolated D3D12 Forward Mobile shader render: successful, no shader
errors; the previous shader shows patch seams in an otherwise identical probe,
and the corrected shader renders a continuous field. The production starter
Mobile capture did not finish scene restore within its 120 s desktop-renderer
limit; no complete gameplay capture or Thor visual approval was obtained.
The Thor was not connected to ADB during this session.

**Delivery blocker:** v69 ARM64 export was attempted twice. The correctly
quoted preset reaches validation but fails because this host has no configured
Java SDK and no Android SDK build-tools/apksigner. No APK was produced or
installed; an ARM64 `libvoxel` package check and on-device review remain due.
The export-generated import metadata and UID file were removed from the branch.
# Hearthvale — v67 post-stroke-backlog fix on the Thor (2026-09-21)
## 2026-09-21 (round 13) — v67: per-frame native-paste box reset shipped; backlog death-spiral eliminated, small residual single-frame spike remains

**Fix (in this commit, `scripts/terrain_backend.gd`):** `_flush_native_updates` now
resets `_pending_native_min/_max` after each per-frame native paste. Root cause:
`_write_region` extended the pending box monotonically across the whole stroke, so
each per-frame paste re-pasted the **entire accumulated stroke AABB** to
`VoxelTerrain`. The engine's `try_schedule_mesh_update` dedupes only while a block
is already in the pending list; once its previous mesh task completed, the next
re-paste re-queued it for a **full re-mesh of identical data** — over a ~2.6 s
stroke at 60 fps every touched block was re-meshed ~150×, building the unbounded
backlog that saturated the main thread (the ~0.8 s user-visible freeze and the
16 s death spiral from round 12). Per-frame pastes now cover only that frame's
brush steps (~1–2 mesh blocks). Undo/redo (`_apply_command_region`) remains a
single one-shot paste — a brief spike, not a repeated re-queue, so no chunking
needed there; initial/checkpoint load paths untouched.

**Also (in this commit, `scripts/m1_scene.gd`):** the bridge `perf` action now
returns an `engine` field — `Engine.get_singleton("VoxelEngine").get_stats()`
(thread-pool tasks/active threads, per-category task counts) — so native backlog
can be watched live.

**Tests (headless, all green, 0 failures):** m1_scaled_backend_test (44 checks),
startup_mesh_vertical_band_test (4), sculpt_test (188), sculpt_smoothing_test (23),
debug_bridge_action_test (15) — 274 checks total.

**v67 built, verified, installed:** code 67, `org.hearthvale.game.test.m2night`,
one ARM64 `libvoxel`, in-place update on the Thor (192.168.1.15:38865).

**On-device result (announced strokes + undo each):**
- Engine backlog mechanism **gone**: peak meshing+main_thread task count **2**
  (vs unbounded growth on v66), `time_request_blocks_to_update` **0.00 ms**
  through the whole post-stroke window (vs 97 ms on v66), no death-spiral on
  repeated strokes. The user-reported multi-second freeze class is fixed.
- **Residual:** one ~137–500 ms single-frame spike immediately after stroke
  release (open-field stroke at [48,8,48]: 137 ms, scene 25.7 ms; house-pad
  stroke: ~500 ms sustained, scene < 42 ms), then clean recovery. A distinct,
  much smaller phenomenon from the v66 backlog freeze.
- **Caveat — device was thermally throttled** the whole session (idle period
  27 ms ≈ 37 Hz, not 60; the device had been running 1.5+ h since the v66
  round). Per project rules these absolute numbers are not valid performance
  evidence; the engine-task metrics above are refresh-rate-independent and
  valid. The residual spike must be re-checked on a cooled Thor (reboot/
  screensaver first), and dissecting it further needs a per-frame
  pre/scene/post ring-buffer probe (current `frame_clock_probe.gd` only keeps
  300-frame window averages, which dilute single-frame spikes).

**Bracket-interpretation correction (supersedes a round-12 note):** the
frame_clock brackets actually *partition* the frame (pre = previous probe tick →
this scene start; post = scene end → next probe tick; pre+scene+post = period),
so there is no unmeasured gap — the root-level `VoxelEngineUpdater` runs after
`current_scene` and sits inside the `post` bracket. The v66 "only ~28 ms of a
~111 ms frame" reading was a window-average dilution: the ~28 ms average period
meant the *entire 12 s window* was degraded (backlog drain period), not a single
spike frame.

**Not in this commit:** the WIP cottage brick-band tweak in
`scripts/cottage_visual.gd` (thinner/sparser band) remains uncommitted, pending
the user's keep/revert decision.

**Device state:** app running on the starter valley in the terrain (Raise) tool
with the debug bridge up; all probe strokes were undone after measurement.
Thor is still warm — cool to near-ambient before the next absolute-fps round.

## 2026-09-20 (round 12) — post-stroke freeze: mechanism fully identified in the pinned voxel engine

User confirmed the post-stroke freeze is still present on v66 (~0.8 s, fps 60 → 9 → recover). Investigation this round eliminated every candidate we could measure and **pinned the mechanism in the native engine** (Zylann/godot_voxel v1.7x, commit 75d3c6d996ed2331c80edcd8c3ebc947afc0f041, per `dependencies.lock.json`).

**A/B results (bridge `tune`/`probe_nodes` on the live app, same world, same stroke):**

| Arm | Post-stroke dip | Notes |
|-----|----------------|-------|
| v66 as-is (all native nodes on) | fps → 9 for ~0.8 s, then recover | baseline, user-confirmed freeze |
| `VoxelTerrain` process disabled | dip reduced but NOT eliminated (~0.6 s, fps → 14; commit RTT 77 ms vs 131 ms) | terrain's per-frame sweep contributes, but the dip is not solely there |
| `VoxelViewer` disabled (6-round interleaved) | **no measurable difference** (worst RTT ~2.65 s both arms, identical dip profile) | viewer / mesh rendering is NOT a contributor |

**What was also eliminated:** the scene's own `_process` (frame_clock brackets pre ~10 ms / scene ~10–12 ms / post ~7.4 ms ≈ 28 ms of a ~111 ms stalled frame — the freeze happens in a *gap* outside our measured code); water re-simulation (0 cells pending/resampled after a raise stroke — the v63 fix holds); the native edit itself (`last_edit_ms` ~1 ms).

**The mechanism (verified in engine source, v1.7x):**

1. **`VoxelEngine::process()` is called every frame** by `VoxelEngineUpdater_dont_touch_this` — a root-level node (child of SceneTree root, outside the gameplay scene tree; created once by `ensure_existence()` when the first voxel node is ready; `process_mode = PROCESS_MODE_ALWAYS`). It lives outside both the scene tree and our frame_clock brackets, which is why the freeze was invisible to every in-scene probe.

2. Inside `VoxelEngine::process()` there are **three phases**, and only one of them is budgeted:
   - (a) **dequeue completed worker tasks** → `apply_result()` per task — **UNBOUNDED**. (`apply_result` itself is a cheap struct handoff — the `ArrayMesh` is fully built on the worker by `MeshBlockTask::build_mesh()` — so this is only a problem when the *count* of completed blocks is huge.)
   - (b) **time-spread task runner** — budgeted by `main_thread_time_budget_usec` (the only budget knob).
   - (c) **progressive task runner** — **UNBOUNDED**.

3. **`VoxelTerrain::process()`** (fixed-lod terrain) runs its own per-frame **block-request sweep** on the main thread — the `time_request_blocks_to_update` stat, measured **97 ms** in one post-stroke sample. The stats API only exposes 7 fields (no worker-pool depth), so queue size during the dip can't be read today; `VoxelEngine::get_stats()` *does* exist in C++ (thread-pool tasks remaining, active/total threads, per-runner pending counts, gpu tasks) but is **not wired into the debug bridge**.

4. **Death spiral observed:** after dozens of scripted probe strokes accumulated a mesh backlog, a single `tune` call didn't answer for **16+ seconds** before the app was force-stopped (21:28:18, `forceStopPackage` in logcat — a user/launcher stop, *not* a crash; no FATAL/SIGSEGV/ANR). The unbounded phases (a)+(c) plus the 97 ms sweep mean a large backlog keeps producing main-thread work every frame faster than workers clear it.

**Fix candidates (none require rebuilding the engine extension):**
- **Cap the main-thread drain rate** via the `main_thread_time_budget_usec` property (phase b only) — testable through the bridge if we extend `tune` to expose it, but phases (a)/(c) are still unbounded.
- **Time-budget / rate-limit the request sweep** (phase in `VoxelTerrain::process`) — that's the 97 ms spike; our `terrain_backend.gd` wrapper could stagger which region is requested per frame.
- **Wire `VoxelEngine::get_stats()` into the debug bridge** to finally *see* queue depth during the dip and A/B each phase (requires a small bridge-only GDScript change if the binding is reachable, or a one-time extension rebuild if not).

**Device state at end of round:** the app was force-stopped during the test and is **not running** (user will relaunch; world save is intact — the user is fine with probe-stroke residue and we're not attached to the test world). **The Thor is hot (~51–55 °C)** from the stroke testing — let it cool to near-ambient (screensaver) before the next measurement round; throttled numbers are not valid evidence.

## 2026-09-20 (round 11) — v66 installed on the Thor for user performance testing (main @ 3467344)

Built from exact `main` state (`3467344`; the wip cottage brick-band tweak in
`scripts/cottage_visual.gd` was stashed out of the build and remains uncommitted).
Preset bumped to v66 in `85ca612`. Exported with the local debug keystore
(SHA-256 `D4:4A:59…`); APK verified: exactly one ARM64 `libvoxel` inside.

**Device state:** `org.hearthvale.game.test.m2night` at **versionCode 66
(2.0.1-m2night-v66)**, in-place update v64 → v66 (`adb install -r`, ~5 s,
incremental). Package name note: the round-10 line below says
`com.ayn.thor.hearthvale.m2night`, but `pm list` shows the m2night test package
on this device is `org.hearthvale.game.test.m2night` (the AYN-branded name is
not installed). App was not running after install; user launches for the perf
run. ADB daemon was restarted this round (was down); device 192.168.1.15:38865
reached as usual.

## 2026-09-20 (round 10) — v63: terrain→water sync localized (8d1e479) — no more full water resample on any tool's commit

**Delivered on the Thor (v63, commit 8d1e479), installed and running.**

**Cause:** `m1_scene._sync_water_visual()` (base scene, inherited by the M2
scenes) called `refresh_surface_from_bounds(Rect2(-INF, -INF, INF, INF))` on
EVERY committed landscape edit — terrain commit, undo/redo, bridge strokes.
With the current 76×76 world that is a 38,000-cell resample + full water
reconstruction per commit. v62 A/B: the water raise stroke's release frame
spiked **304 ms** (78th percentile of all frames — the user-reported "~1 s
release freeze") and sustained water FPS was 22 (29 for landscape raise,
36 for landscape lower; the 41 ms water-lower peak is a 1000-iteration
brush-step loop, not water). `water_visual.gd` itself is already incremental;
the scene was bypassing that seam.

**Fix (8d1e479):** scene passes the committed AABB to the new
`refresh_surface_from_bounds_aabb(aabb)` (margin already inside the method;
rect-only call kept for full refreshes) — one commit now re-samples at most
~16×16 cells instead of 38k. Undo/redo recompute bounds from the inverse
strokes; strokes with no commits leave water untouched. **A/B (v62→v63, same
world, same stroke scripts, same 1.3 ms device clock drift):** release-frame
peak 304 ms → **43 ms** (7×); sustained water 22 → 31 fps (5× faster frame
time); landscape raise 29 → 35, landscape lower 31 → 37. The 41 ms
landscape-lower peak remains (brush-step loop, separate candidate).

**Tests:** `tests/water_visual_test.gd` grew 8 → 15 checks, all passing
headless: the new AABB path equals the full-path result on identical input,
and a 0.25 m edge patch leaves every other cell's height byte-identical
(locality proof). Added to `.github/workflows/water.yml`.

**Not delivered (flagged, needs user call):** (a) the 41 ms landscape-lower
peak (brush stroke step loop), (b) 30 ms terrain meshing cost per stroke
step, (c) 3×32 KB water buffer churn per stroke (poolable). **Unrelated red:
the delivery workflow is failing ~24 h for a CI-infra reason (the release
build's `--import` step OOM-killed on the CI runner, plus the Android
`local.properties` gotcha); not caused by this session's commits. v63 was
built and verified locally per AGENTS.md.**

**Device:** 192.168.1.15:38865, m2night test package `org.hearthvale.game.test.m2night`
(same debug keystore `D4:4A:59…`), auto-resumed from
the saved world.

## 2026-09-20 (round 9) — v62: planting plots re-authored as 1/16-grid MagicaVoxel meshes (d704b39 + 2e522ee), verified in-game on the Thor

The user called the planting fields "at the coarser scale" and asked for them
as voxel meshes via the MagicaVoxel MCP. Both halves of the job:

- **Art (d704b39):** the six committed plot sizes (1.0×2.0, 1.5×1.0, 2.0×3.0,
  2.25×2.25, 3.0×1.75, 3.0×2.0, 3.5×2.5) each authored natively on the 0.0625
  presentation grid (16×32 … 56×40 cells, 544–2,832 tris) — wooden rims, furrowed
  soil, individual crops/flowers, no cell stretching. Sources at
  `assets/source/magicavoxel/hearthvale_garden_{style}_{W}x{H}.vox` (+ `.obj`,
  `.mtl`, receipt) with `garden-plots.authoring.json`; provenance in the README
  and the CI provenance script (new `assert_garden_assets` block).
- **Runtime (2e522ee):** `m2_composition_visual.gd` loads the authored mesh for
  a committed garden when `size×16` matches an authored variant (yaw rotates
  the node, vertex-colour tint follows the record colour), else the old 0.125
  procedural build stays as fallback. Preview meshes use the authored mesh too.
  New headless `tests/m2_garden_asset_test.gd` (23k checks: variant coverage,
  winding/solidity, cell counts ≤ 3,000/plot, tint path) registered in
  `tools/test-cottage-shard.ps1` and the CI gate.

**v62 built, verified and installed:** `builds/hearthvale-m2night-v62-2e522ee.apk`
(versionCode 61, `…m2night`, exactly one ARM64 `libvoxel`, in-place update
~0.5 s). In-game (bridge): all six committed gardens
`Garden_<id>` render from the authored meshes — the starter-valley trio plus
three the user placed in an earlier round; close-ups at (16, 33.75) and
(20.25, 21) show the finer grid, framed beds, individual crops. The 1.0×2.0
bed at (30.25, 35) sits against a cliff: every zoom drifts into the slope
(known camera gotcha), so it was verified by record/mesh coverage instead.

**Gotcha:** a bright fine white/yellow grid near the cursor in screenshots is
the **user-session Precision overlay**, not an asset bug — confirmed by
`probe_nodes` A/B (hiding all six `Garden_<id>` nodes left the grid in place).

## Delivery workflow state (2026-09-20) — not caused by this session's work

`Hearthvale verified Drive delivery` has been RED on all 30 runs examined
(~24 h; every push since ~v52). Failure mix across runs:
- **Flaky ready/timeout gates on loaded Windows runners**: `m1_landscape_test`
  ("native landscape scene ready", 30 s deadline), `m1_controller_test`
  ("native backend ready"), joined-roof "Mobile review timed out", and one
  roof-render count check captured while `WORLD_STATS` showed the scene at
  1 fps. The same tests passed in earlier runs (e.g. fabd47b's run) —
  timing-sensitive, not assertion regressions.
- **Persistent pre-existing failures** (present before this session's code):
  `m2_upper_storey_auto_windows_test` ("new upper storey is populated with
  automatic windows" / "several exposed facade directions" — failed in both
  of the two most recent runs) and one run's "packed-earth plaza remains
  physically collidable after excavation".
- **Local reproduction**: on this box the same ready-gate tests fail
  identically on a worktree at `fabd47b` (pre-session v58 code) as on HEAD
  (voxel backend never reports ready, `updated_blocks:0`) — so no commit in
  this session is the cause. Local delivery evidence remains the targeted
  green batches in the v58–v62 entries above.

**Open question for the user**: treat the workflow red as the known
M2 in-flight state (upper-storey auto-windows), or invest in stabilizing
the timing-sensitive gates?

## 2026-09-20 (round 8) — v58: arch canopy detail re-authored natively in MagicaVoxel (e0096f1), verified in-game on the Thor

After the b9c79a4 1/3 reduction the user asked for the canopy to be "brought
up to the level of detail" of the other props and clarified the method: **no
model scaling — re-author the detail in MagicaVoxel**.

**Why the detail was lost:** a 3×3×3 majority-vote decimation cannot preserve
a scattered mosaic. The original canopy face was ~14.5% flowers/leaves (1–2
cell motifs on the 144 grid); after decimation the band is only 1–2 cells
thick, so the motifs collapsed into sparse 2×2 blobs and a flat brown rim.
A naive 2:1 position mapping of the original motifs was prototyped and
rejected (it turned the thin band into confetti).

**Fix (e0096f1, pushed to `task/water-river`; supersedes pre-amend hash
7557398, which the v58 APK filename still carries):** re-authored the canopy
faces in MagicaVoxel on the **same 40×48×24 grid** (no scaling, no geometry
change — 6,710 voxels / 1,720 tris, identical bounds): face cells of both
canopy bands re-painted into a scattered mosaic of 1–2 cell pink/white/
purple flowers and light/dark leaf clusters approximating the original's
face coverage; bumpy top edge preserved. `.obj`/`.mtl`/receipt re-baked; the
tracked `.res` re-baked via `tools/magicavoxel/bake_mesh.gd` (157,847 B, 9
surfaces, 6,534 verts — the first v58 build had picked up the stale pre-bake
`.res`, hence a second export).

**v58 built, verified and installed:** `builds/hearthvale-m2night-v58-7557398.apk`
(versionCode 58, `org.hearthvale.game.test.m2night`, exactly one ARM64
`libvoxel`, sha256 `e0284d4f…`, in-place update 2.98 s). World load → bridge
up in ~38 s. `composition_dump`: arch record id 108 at [17.625, 22.375],
size [2.375, 1.0], yaw 2 — the arch placed during the v55 review round
survived the in-place reinstall. In-game camera
close-up (cursor orbit to the arch + trigger zoom to 8 m): the canopy reads
as a leafy hedge with a scattered flower mosaic and woody framing, matching
the approved original's character at 1/3 scale. Two screenshots shown to the
user.

**User visual verdict on the in-game v58 arch: APPROVED** ("yes that's the exact
vibe"). The placed arch is the v55 review-round instance at [17.625, 22.375]
(yaw 2), in front of the cottage; if a different spot is wanted it can be
replaced with the furniture verbs or manual play. Device was
force-stopped after the captures (screensaver; thermal cooldown). Bridge:
port 47123, `cursor_set [x,y,z]` (flat args, not nested), `set_axis
trigger_right/trigger_left` for zoom (8–52 m), right stick orbits the
camera around the cursor.

## 2026-09-20 (round 7) — flower arch reduced to a third (b9c79a4); v57 verified, install pending on device drop

The user rejected the 2× arch on review: "That's the FLOWER ARCH??? Way too
big, make it a third" — and, from an earlier capture the 2× bake's voxels read
chunkier than the trees. Root cause of the second point: the 2× supersample
bake doubled every feature to 2 cells (0.125m) at the 0.0625m import pitch.

**Fix (b9c79a4):** `hearthvale_flower_arch.vox` 120×144×72 → **40×48×24**
cells via a deterministic majority-vote 3×3×3 decimation
(`tools/magicavoxel/third_arch.py`) → **2.5m tall × 3.0m wide × 1.5m deep**,
6,710 voxels / 1,720 tris, and 1-cell-thick features back at the 0.0625m
pitch shared with the trees. `.obj`/`.mtl`/receipt re-baked, `.res` re-baked
via `tools/magicavoxel/bake_mesh.gd` (9 surfaces, 3,312 verts). Placement
footprint 2.375×1.0 (0.125-grid); `COMPOSITION_MAX_SIZE` reverted to its
original 6.0 (the 7.5m exception only existed for the rejected 2× arch).
Tests green: street_prop_asset checks=12751/0, furniture_placement
32/0, build_browser 254/0. (`m2_build_browser_capture` still requires the
actual Mobile renderer — not runnable in headless, unchanged.)

**v57 built and verified:** `builds/hearthvale-m2night-v57-b9c79a4.apk`
(versionCode 57, `org.hearthvale.game.test.m2night`, exactly one ARM64
`libvoxel`, 39,948,262 B; same debug keystore → in-place update).

**Pending (Thor dropped off ADB mid-build):** install v57 in place (never
uninstall), launch, re-place the arch on the lane in front of the white
house (`furniture_select flower_arch` → `cursor_set [28, 8, 28.5]` →
`furniture_commit` — the v55 anchor; the round-6 placement did **not**
survive the v56 force-stop), verify the record with `composition_dump`,
clean-quit/reload survival check, and before/after screenshots for user
visual acceptance.

## 2026-09-20 (round 6) — v55 placed the arch on device at the lane end (28, 8, 28.5); user acceptance pending
(The round-6 placement was lost when the v56 update force-stopped the app
before its autosave; the live world was back to the 14 starter compositions.
) 

v55 (commit d4435e2, versionCode 55) installed in place over v54 and the
2× flower arch is now **committed in the live world**: `furniture_select
["flower_arch"]` → `cursor_set [28, 8, 28.5]` → `furniture_commit` →
`{"committed": true}` on the **first candidate**. The v53/v54 anchor
(28, 8, 30.5) is rejected by `_commit_detail` ("Furniture overlaps a
home") because it sits inside the village_gable footprint (house centre
(28, 35), front lane ends at (28, 32.75)); 28.5 is the first clear spot
south of it — the arch now gates the lane end in front of the white
house's entrance, matching the approved v53 composition.

The bridge zombie-slot fix is proven live: three sequential bridge
sessions in one app launch (load chain → placement probe → camera
orbit) each got the slot — the failure mode that cost the v52/v53/v54
sessions.

`composition_dump` crash found on device: the handler called
`ls.has("composition")` on the `LandscapeState` **instance**
(RefCounted has no `.has()`) → SCRIPT ERROR → `{}`. Fixed in
`m1_scene.gd` (use `.get()`; records are plain Dictionaries in
`landscape_state.composition`). The record itself is already confirmed
by the committed:true response + screenshots; the fixed dump will give
the formal record in v56.

Screenshots (device, 07:05, /tmp/arch_v55_placed_1..2.png): arch visible
between the white house and the lane, well + paving in frame; second
shot shows the hamlet from the opposite side with the arch over the
lane end. **Pending: user visual acceptance**, then v56 (dump fix
verified: composition_dump shows the flower_arch record) and the
final M2 handoff build.

## 2026-09-20 (round 5) — v54 placement was an artifact; v55 adds real furniture-placement verbs + bridge zombie-slot fix

**v54 verdict (revised):** the arch was **not** placed on the v54 build.
`/tmp/place_arch_v54.py` used verbs that do not exist in the bridge: a
top-level `context` command, a top-level `key` command, and
`furniture_select` — which was never implemented in
`m1_scene.debug_test_action` (the only verbs are state/composition_dump/
shell_keys/cursor_set/select_tool/view_context/cancel/undo/redo/
world_stats/mesh_survey/tune/perf/reset_peaks). So in v54 only
cursor_set ever ran; the "no rejection, no errors" read in round 4 was
the script talking to itself, not to the scene. (The v53 in-memory
placement in round 4 remains the only real placement so far.)

**Why the v54 process (pid 1895) went silent to bridge pings:** not a
meshing burst. The game was healthy (27 ms frames, menu showing, 6 %
CPU) — the debug bridge holds a **single client slot** and it was
occupied by a zombie: the placement script's socket sent data, then
the TCP close arrived *inside* Godot's buffered-packet processing, so
the peer keeps reporting `CONNECTED` with 0 available bytes forever.
The pump only recycled never-got-data peers (3 s) and `NONE`-status
peers (EOF), so the zombie held the slot and every later session was
silently dropped — one usable bridge session per app launch.

**v55 = v54 + two changes (commit pending on tests):**
1. `scripts/m1_debug_bridge.gd` — tracks `_last_data_ms`; recycles a
   data-sent client after 60 s idle (hard cap) or 10 s idle when a new
   connection is queued. Sequential debug sessions can't trip this.
2. `scripts/m1_scene.gd` `debug_test_action` — new debug verbs that call
   the **same handlers real input uses**: `furniture_select [style_id]`
   → `_choose_furniture_style` (the build-browser entry point,
   m2_scene_street_furniture) and `furniture_commit` → `_commit_furniture`
   → shared `_commit_detail` transaction (add_composition). M2-only:
   a scene without the furniture layer reports an error, not a silent
   no-op.

**Placement protocol (single long-lived session, `/tmp/place_arch_v55.py`):**
ping → state → `action furniture_select ["flower_arch"]` →
`action cursor_set [28, 8, 30.5]` → state → `action furniture_commit`
→ `action composition_dump` (expect one record with kind=furniture,
style_id=flower_arch anchored at (28, 8, 30.5)) → world_stats. Target
spot: white-house garden side (same anchor v53 used).

**Pending:** 4 local suites (debug_bridge_action, m2_bridge_placement,
m2_furniture_placement, m2_bridge_state) → commit+push → build v55
(same keystore, verify one ARM64 libvoxel) → install in place →
launch → placement script after world load → composition_dump evidence
+ `adb exec-out screencap` → user visual acceptance.

## 2026-09-20 (round 4) — v54 on device; 2× arch verified as placing, record check pending

The v53 uninstall was **not** needed: the current device's debug.keystore
(9/18, `D4:4A:…:4F`) matches the keystore v53 was signed with, so
`adb install -r` updated v52 → v53 in place. On the v53 build the 2×
arch **placed successfully** at (28, 8, 30.5) via
`furniture_select` flower_arch → `cursor_set` → A: no rejection, no
errors, +108 prop meshes (≈ the 2× arch's cell count). That placement was
in-memory only — the v53 process was killed by the v54 update and the
`m1_checkpoints/` directory is empty, so nothing persisted.

**v54** = v53 + commit `f02fdd8` (debug-only `composition_dump` bridge
verb that dumps `landscape_state.composition` records, so a placement can
be verified against the authoritative record instead of mesh counts).
APK: versionCode 54, signed with the same keystore, verified (exactly
one ARM64 `libvoxel*`; the 99 KB 2× arch mesh resource is in the
package), archived as `builds/hearthvale-m2night-v54-0415.apk` (+idsig).
Installed in place and launched.

**Device state at handoff:** the v54 cold start is in its first-load
meshing burst, which has run unusually long (≈9+ min; the device is
thermal-throttling — it ran 84 °C after overnight use and climbs back to
≈79 °C during the burst; v53's identical burst took ≈3 min when the
device was cooler). Main thread sleeps while a worker spins ≈70 % of one
core with CPU time still rising — consistent with slow meshing, not a
lock (no errors in logcat; all in-memory .res assets in v54 are
byte-identical to v53's). The debug bridge listens on TCP :47123
(forwarded) but does not answer pings while the main thread is blocked.
A background waiter (`bg-44`, pings every 40 s for 20 min) is watching.

**When the bridge answers:** run `/tmp/place_arch_v54.py` (context
building → furniture_select flower_arch → cursor_set [28,8,30.5] → A →
composition_dump) and confirm the dump shows one flower_arch record
anchored at (28, 8, 30.5); then screencap from outside the cottage to
capture the walk-through scale for visual acceptance. If the burst does
not finish, force-stop, cool the device (screensaver, target < 70 °C),
relaunch and repeat — a thermally throttled run is not valid evidence.

Notes: `tests/m2_hamlet_composition_render_test.gd` reports
`M2_HAMLET_RENDER_UNAVAILABLE` under `--headless` (needs a display) —
not run here, same as prior rounds. Bridge = newline-JSON over
`adb forward tcp:47123 tcp:47123` (not HTTP).

## 2026-09-20 (round 3) — street-scale arch placement fix (v53) + pending uninstall decision

The 2× street-scale flower arch would not place on device: banner said
"Furniture is outside the editable world or detail limit". Root cause:
`COMPOSITION_MAX_SIZE` in `scripts/landscape_state.gd` capped every
composition anchor at 6.0 m (the original small-prop limit); the 2× arch
anchors at 6.875 m. Fix (commit `08c1c99`): cap raised to 7.5 m (still far
below building footprints) + regression block in
`tests/m2_furniture_placement_test.gd` (6.875×3.0 commits, 8 m rejected) —
32/32 checks pass headless.

**v53 APK is built and verified** in `/tmp/hv-v42/builds/hearthvale-m1-debug.apk`
(39,927,407 bytes, signed, exactly one ARM64 `libvoxel*` in the APK,
versionCode 53). **NOT yet on device**: in-place update fails with
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` — the installed v52 (updated 02:47
Sept 20) was signed with a Godot debug keystore from a previous session's
environment that no longer exists on this machine (only the Sep 18
`/root/.local/share/godot/keystores/debug.keystore` is here, and the
device rejects it).

Device data check before any uninstall: the app's `files/` holds **no
world data** — `m1_checkpoints/` is empty (the two stale Sep 19
checkpoints were cleared at 02:55), only shader/vulkan caches remain.
The current hamlet is a fresh starter regeneration, so a fresh install
loses nothing of the user's. **PENDING USER DECISION** (asked, user went
to sleep): approve one-time uninstall of `org.hearthvale.game.test.m2night`
+ fresh v53 install. Same one-time uninstall was needed for v51.

Next steps when approved: `adb -s 192.168.1.15:38865 uninstall` →
`adb install` the v53 APK (keep the standard debug keystore identity) →
launch, init bridge (TCP :47123, newline JSON, **not** HTTP) → place arch
via `furniture_select` flower_arch + `cursor_set([28, 8, 30.5])` + commit
(known-good spot from the v47 session) → screenshots for visual
acceptance of the walk-through scale. Game was force-stopped before the
user went to sleep; the device app is currently the (uninstallable-over)
v52.

## 2026-09-20 (round 2) — "B does nothing in water mode" root-caused + idle presentation gate

User report: in water mode B no longer cancels the outline; later, dpad-right
"does nothing" in water mode. On-device trace (temporary TRC-HEAD/TAIL event
probes at the head and tail of the `_input` chain, bridge `input_trace`
toggle — **removed after use**) found no missing press and no mid-chain
swallowing: the "unresponsive" dpad press was auto-repeat (a ~300 ms hold
generates 7-8 repeats that wrap the 8-tool list). **Root cause: the B-button
passthrough at the top of `m2_scene_water._input` was lost in an earlier
edit** — with `water_placement_active`, the B release event fell through to
the root `_input`, where `m1_cancel` only maps to `ui_cancel` (back button),
and the water placement was still active, so the cancel was refused.
Fix restored: `if water_placement_active and event.is_action_pressed("m1_cancel"):
return` in `m2_scene_water._input` (head of the chain, before super).

**Second idle stall found the same day:** with the raise tool selected and
no input, `_process` spent ~16 ms/frame on building/particle presentation
(`cottage_visual` massing rebuilds + particle `process`) because the idle
skip keyed on `(tool, radius, cursor, stroke, view)` changed every frame with
the drifting camera cursor. New gate: presentation is skipped entirely while
a terrain tool is active and no stroke is in progress
(`m1_scene._skip_present`, re-verified on device with the debug
`shell_keys` probe: idle key stable across 10 s, 38-40 fps).

**FPS A/B (this round): in progress** — see below for the numbers.



## v46 — full-world visibility: viewer radii now derive from the world extent (2026-07-20, on-device verified)

The user's "the world is not fully loading" complaint was real: the runtime
visual viewer was hardcoded to a 128 m radius and the data viewer to 64 m,
but the m2night test world is ~145 m wide (diagonal ~213 m), so terrain beyond
those radii silently never meshed — permanent gaps at the world's edges no
matter where the camera went. Fix (`terrain_backend.gd`): both radii now
derive from the actual world extent — visual = 1.25 × (max half-extent +
12 m camera overhang) → 266 m on the m2night world; data = half-diagonal ×
1.414 → 106.5 m. Starter-world values stay byte-identical (128 m / 64 m);
`m1_scaled_backend_test` pins updated to the formulas (44/44). On-device v46
(versionCode 46, production preset, exactly one ARM64 libvoxel, debug
keystore identity unchanged): **25 s + 20 s camera pans to the far corner of
the valley — full terrain rendered everywhere, no pop-in, no gaps**; idle
25.3–25.8 ms (~39 fps; pre_ms 13.8–14.9, scene 0.8) and 25.3 ms during
panning — **no fps regression vs v45's 38–40 fps idle** (the bigger viewer
costs nothing steady-state; the first load after install pays a one-time
full-world meshing burst of ~2 min at ~13 fps that recovers on its own —
expected, not a regression). v46 also carries the cottage brick-coursing
cosmetic (see below) — it renders correctly in on-device screenshots (red
brick + mortar coursing on the Tudor cottage); the user's explicit visual
approval is still pending. **Bridge gotcha:** the debug bridge is a raw
newline-delimited-JSON TCP server, **not HTTP** — `curl http://…:47123/…`
always fails (rc:1 / "HTTP/0.9 when not allowed"); send
`{"cmd":"ping"}\n` over a plain socket instead.

2026-09-20, branch `task/water-river`. Current user focus: "the world is in
fact not fully loading — measure avg FPS before/after" plus the newer
reports (2026-09-20): still lots of lag during water creation, 1-2s freeze
after raise/dig strokes. The v43 full-valley record below remains the
history; the 2026-09-12 packed-earth handoff is preserved at
`reports/handoffs/HANDOFF-a85d28d.md`.

## v49 — idle terrain-tool re-meshing killed + real frame-delta peak probe

The v43 "20m -> 128m viewer" fix was a red herring for the "world not
loading" report: the user's world was fully meshed (mesh_survey), but the
*live gameplay terrain backend* was pinned at `startup_view_distance = 20`
(the old M1 constant the M2 water ticket never widened) and the live
camera orbits at ~7-12 m, so most of the valley's gameplay-mesh cells were
being streamed in and out of a 20 m residency radius as the camera moved —
perpetual churn that showed up as (a) terrain that appeared to vanish at a
distance and (b) a constant CPU floor. v48 (yesterday) set the live backend
to the full 128 m world; on the user's test world (266k mesh cells, ~48k
cottage cells, 37k water cells) that raised steady idle from ~30 fps
(28.4 ms, CPU-saturated) — and it is the correct architecture (residency
== whole finite world, same as the visual viewer).

v49 adds two things on top of v48:

1. **Presentation gate (the actual idle fix).** `_update_brush_preview()`
   (m1_scene.gd) recomputes the sculpt preview + terrain target *every
   frame while a terrain tool is selected* — and the user always has the
   raise tool selected, so idle gameplay was re-meshing the brush preview
   (~17 ms) and re-running the path terrain-ownership update (~16.5 ms) on
   every single frame, even with zero input. Now the recompute is gated by
   a key of (tool, brush radius, cursor, stroke active, view context,
   target valid); the key changes only on real input, so idle frames
   cost ~0 ms and the one-frame input latency is acceptable for a
   controller-driven game. The gate lives next to the call in
   `m1_scene_building_camera.gd` (`_should_update_brush_preview`); the
   preview centre is only part of the key while a stroke is active
   (the centre itself drifts every frame with the camera ray and must
   not keep the gate open at idle).
2. **Real worst-frame measurement.** The old worst-frame tracker only saw
   `process`/`presentation` CPU; the multi-second freezes are GPU
   backpressure that CPU probes never see. The tracker now keeps the
   maximum real-time delta between `_process` callbacks (frame period the
   player actually waited) alongside the CPU peak.

**v48 -> v49 A/B, same m2night build otherwise, on-device bridge**
(`/tmp/hv-v49-ab2.jsonl`, strokes + 12 s idle windows, peaks after
`reset_peaks`):

| window | v48 | v49 |
|---|---|---|
| idle, raise tool selected | 30 fps / 28.4 ms | **38-40 fps / 25-26 ms** (peak frame 28-33 ms) |
| raise stroke (2.2 s, small) | ~30 fps steady | ~20 fps during; **one 145.8 ms spike frame** right after release (process 46 ms: sculpt 21.7 + presentation 17.4 + camera); recovers to 39 fps in ~1.5 s |
| water stroke (small stream) | multi-second freezes (pre-v40 fix) | **fps drops to 7-19 and stays ~19 fps for 6-8 s** after the stroke (per-frame water update 16.7 ms; 149 ms spike at stroke start); recovers to 39-40 in ~8 s |

Conclusions: the gate fix is worth +8 fps idle and is the fix for the
"not loading" churn. The remaining user-visible issues are real but
smaller than reported: a ~150 ms single-frame stutter on terrain stroke
commit (scales with stroke size — a user's big raise/dig can approach the
perceived "1-2 s"), and water strokes on the user's large test world leave
a sustained 19 fps degradation for ~8 s (GPU-bound: 52 ms frames vs 34 ms
CPU; the v40 banded probes + budgeted drain removed the multi-second
freeze but not the rebuild load).

Next (approved follow-ups, not yet done):
- Water stroke cost: profile the per-stroke ribbon/extend rebuild on a
  37k-cell body (per-frame `m2_scene_water` update 16.7 ms during stroke,
  ~18 ms unaccounted GPU in the 52 ms frame); budget/split the post-stroke
  water visual rebuild like the drain was.
- Terrain stroke-commit spike: the rebuild batch (sculpt 21.7 ms +
  presentation 17.4 ms in one frame) is unbudgeted; extend it over frames
  or cap the per-frame cell budget so commit stays under ~30 ms.
- Cottage brick coursing art pass is implemented in
  `scripts/cottage_visual.gd` (1x1-cell bricks, 0.5-cell joints, same 33%
  mortar ratio; Tudor tone patch bias 4x3 -> 8x6 cells); shipped inside v46
  and visible on device — awaiting the user's explicit art approval.

Device: m2night v46 (`versionCode 46`, `/tmp/hv-v42` production-preset
export, exactly one ARM64 `libvoxel`) on 192.168.1.15:38865. Launcher
activity on current Godot exports is `com.godot.game.GodotAppLauncher`
(the plain `com.godot.game.GodotApp` in the manifest does not exist).
Bridge: `adb forward tcp:47123 tcp:47123` + newline-delimited **JSON**
actions over a plain TCP socket (NOT HTTP — curl will always fail): `state`,
`telemetry`, `perf`, `reset_peaks`, `cursor_set [x,y,z]` to place the
cursor on a known surface point, left stick moves the cursor, right stick
orbits; `press a` + left-stick move = a stroke, `undo` to revert.
The user's test world has 37,374 water cells — treat as the perf baseline.

## v43 — world truncation fixed: visual viewer radius 20m -> 128m (`2a77725`)

Symptom (user-reported, confirmed by `mesh_survey` on device): the valley
ended in a hard diagonal cut into void. The drawing VoxelViewer had
`view_distance = 20` — since 596c5b0 the visual viewer follows the camera
at a 20 m radius, so only a 20 m patch of the 64 m world was ever meshed.
Fix: `RUNTIME_VIEW_DISTANCE_WORLD` 20.0 -> 128.0 (exceeds the 96 m
corner-to-corner diagonal, so every camera position sees the whole finite
map; the data viewer and terrain.max_view_distance are unchanged, so
correctness/data residency are untouched). `m1_scaled_backend_test`
44/44 (it pins only the startup-viewer values, which are unchanged).

**FPS A/B (user-requested), same m2night build otherwise, telemetry
averages on the Thor:** v42 (20m): static 26.45 / drift 26.50 —
v43 (128m): static 34.00 / drift 34.00. The fix is a ~28% fps *gain*,
not a cost: at 20m every camera move streamed mesh blocks in and out
(constant re-mesh churn); at 128m the finite world meshes once and the
in-range set never changes. v43 also shows ~5.7M primitives / ~1600
draw calls / ~565 MB static memory at 34 fps steady — the July 15 fps
full-valley evidence predates collision-mesh removal, so it no longer
applies. Screenshot verified: whole valley meshed, no void cut.

Device: m2night test build v43 installed on 192.168.1.15:38865 (the
production-preset build in `/tmp/hv-v42` is at versionCode 5, untouched).
One-off diagnostics: `adb forward tcp:47123 tcp:47123` + the JSON bridge
(`telemetry` for fps/memory, `mesh_survey` for per-VoxelViewer extents,
`perf`'s fps field is not populated in these builds — use telemetry).
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

- Thor wireless debugging: `192.168.1.15`, current adb port **38865**
  (verified 2026-09-21; ports change on reboot/sleep — re-pair then
  connect). The adb daemon on the workstation drops between some command
  batches: re-`adb connect` and re-`adb forward` at the top of each batch.
- Test package `org.hearthvale.game.test.m2night` is running **v60-b48da22**
  (installed base.apk hash `7ee469f1…`, 39,997,414 B = local
  `builds/hearthvale-m2night-v60-b48da22.apk`; left on the starter valley
  for user visual review). It is stamped `versionCode=59` — the concurrent
  v59 chain's sed left `export_presets.cfg` at 59 and the v60 export
  command re-used it without re-bumping; cosmetic only. Identify builds by
  file name/hash, and bump the sed to a fresh code (≥60) on the next build.
  The repo preset is kept clean (`version/code=5`,
  `org.hearthvale.game`); sed a working copy per build and restore after.
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

## 2026-09-21 — flower arch re-authored at native size (v58) + cottage brick sparse, then re-toned (v59 → v60)

- **v58 (approved in game, `fabd47b`):** the street flower arch was re-authored natively at the 1/3 size (40 x 48 x 24 fine cells = 2.5 x 3 x 1.5 m) in MagicaVoxel staging — canopy, stems, vine and flower colours kept from the approved design, no scaling tricks. User confirmed the in-game result: the exact vibe they wanted.
- **v59 (`0469d05`):** user found the cottage's full brick coursing too busy. Sparse proud accents instead: ~15% of course positions qualify as accent zones, ~55% of those carry a cell, 25% of those pop 2 fine cells (0.125 m) for the few real 3-D bricks; rest sit 1 fine cell clear (reads as tone at play distance). `house_wall_detail_test` 25/25 (408 bricks).
- **v60 (`b48da22`, installed & running, `192.168.1.15:38865`; APK hash `7ee469f1…`, stamped code 59):** user: no red bricks — darker versions of the main wall colour, plus colour-only bricks without bumps. Brick tones are now `wall_color.darkened()` over `BRICK_TONE_STEPS = [0.04, 0.09, 0.14, 0.19, 0.24]` (same warm hue, only weathered; other wall materials derive from their own tone); most accents stay 1 fine cell (colour at distance), the 2-cell pops are the only real relief. Tests on this commit: `house_wall_detail_test` 25/25, `facade_depth_layout_test` exit 0 (30 checks), `cottage_render_stability_test` exit 0 (35 checks) — all headless, no failures. APK verified: exactly one ARM64 `libvoxel`, signed with the debug keystore, 3 s in-place upgrade install, saves preserved.
- **Awaiting the user's visual verdict on the v60 facade** (app left open on the starter valley; the cottage is at world ≈ 13.6/22.4). If the tone contrast wants to be subtler, `BRICK_TONE_STEPS` is the single knob; if the 3-D pops should be rarer, `BRICK_PROUD_RATE`. Close the app back to the Chrome screensaver when the review is done.
- Camera gotcha from this session: the v58-era framing recipe (fresh launch → `cursor_set` on the subject → ~1 s gentle zoom from the 36 m start) is the reliable in-game close-up; the building camera clamps 3.5–28 m, so longer zooms slam into the minimum, and multi-second zoom-out/orbit drifts the framing off the subject. A fresh launch resets the camera to the default view, which already frames the cottage well — for facade shots, skip the zoom entirely.

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

## 2026-09-19 (latest) — v41: path re-mesh skip, water-stroke freezes gone

**Installed:** `org.hearthvale.game.test.m2night` **versionCode 41** =
commit `a1821a5` (task/water-river, **pushed**). Built from `/tmp/hv-perf`
(scripts+tests synced from the commit; local preset override v41; extension
verified in place). Same debug keystore as v40 (in-place update OK).

**Root cause of the residual freezes** (water itself was already fixed in
v40): every terrain commit fires `THOR_TERRAIN_CHANGE`, and the path visual
re-meshed its **entire** painted network (3,525 cells in m2night, 495–1,365
ms on the Thor) even when the edit was meters from any path. Fix:
`M2PathVisual.last_terrain_edit_touches_paths()` checks the commit's
`get_last_edit_bounds()` (with the same 2-cell margin the height cache
already uses) against the painted cells; `_refresh_path_visual` skips the
re-mesh when the painted authority is unchanged and the edit reaches no
path cell (height cache still re-probes the touched columns). Overlapping
edits — including packed-earth excavation transitions, whose edits are by
construction on path cells — still rebuild as before.

**On-device evidence (v41, m2night):**
- Water stroke over the previously-freezing band (cursor 18,7,30 + 4 s
drift): **30 fps throughout**; commit log `path_rebuild_ms=25.2` (was
323–530 ms in v40-era data) and **no** full `THOR_PATH_REBUILD {cells:3525}`
line. Same for the RAISE control stroke → general fix, not water-only.
- Terrain commit itself in this dense world (129k building voxels):
total 539–910 ms per stroke commit (upstream 513–885 ms) — a single
one-shot hitch per commit, same for raise and water; not the multi-second
freeze the user reported. Candidate for follow-up chunking if the user
still feels a hitch in dense worlds.
- First stroke after a fresh load dipped to 6 fps for one round:
once-off shader/mesh warm-up of the houses in view (re-running the
identical stroke warm: 30 fps) — not the path rebuild.

**Tests:** new `tests/m2_path_edit_reach_test.gd` (14 checks, registered in
`tools/test-cottage-shard.ps1`) + scene-level far-edit/on-path assertions in
`m2_path_render_test.gd`. Local: all paths-shard tests pass except
`m2_path_plaza_integration`, which fails **identically on clean HEAD**
(pre-existing, not a regression).

**User visual acceptance: still pending** (test strokes were on the m2night
test world). Device closed to screensaver after testing.

## 2026-09-20 — B-fix delivery + before/after FPS A/B (user requested "measure average fps before and after the fix")

Context: the user re-played the device build (version code 47 — the previous session's
v49 + `_skip_present` gate + B-fix) and reported: (a) dpad tool cycle "goes wrong" —
**not a bug**: a 300 ms test hold generates ~7-8 auto-repeat events that wrap the 8-tool
list; short taps cycle correctly in both directions (verified by matrix: dpad right/left
each step one slot in the right order); (b) B button ignored in the water tool — fixed
below; (c) "still lags a lot during water creation and freezes for a second or two after
raising or digging" — measured below.

The previous session's build-tree source (the `_skip_present` gate implementation) was
overwritten by a later tar sync; only its compiled APK survived. Recovery was therefore
tested empirically instead: built **before48** = HEAD (v49, no gate) and **after49** =
HEAD + this session's uncommitted fixes (B-fix, cottage art pass, world-sized viewers,
tool timeouts), and ran an identical device A/B (same script, same world, same stroke
pattern: 30 s idle → 2.5 s raise stroke → 30 s → 2.5 s water stroke → 60 s; `perf` bridge
endpoint, 2 s cadence):

| window        | before48 (v49)      | after49 (v49 + fixes)   |
| ------------- | ------------------- | ----------------------- |
| idle          | 36-39 fps (27.0 ms) | 37-38 fps (26.3-27.0 ms)|
| post-raise    | 36-38 fps           | 36-38 fps               |
| post-water    | 40-42 fps (23.8-25 ms) | 35-42 fps (no dips) |

Sustained-water stress on after49 (5×3 s water stroke bursts, 0.5 s cadence, 57 samples):
min 33 / median 39 / mean 38.9 fps, **zero sub-25 fps samples**. The 19 fps for 6-8 s
dip recorded in v49's own A/B did not reproduce this session. Raw data:
`/tmp/hv-ab-before48.jsonl`, `/tmp/hv-ab-after49.jsonl`, `/tmp/hv-ab-bigwater-after49.jsonl`.

Conclusions:

- The pending fixes are **not** a measurable fps factor — v49's per-frame presentation
  gate already covers what the lost `_skip_present` gate did. No need to recover the
  previous session's source for perf reasons.
- The user's remaining lag, if still felt, is the GPU-bound large-water-body case
  (v49's open item), not CPU. Next lever if it persists: reduce water visual cost for
  large bodies (chunk/LOD the water mesh), not more CPU gating.
- World was restored after measurement (10× `undo` via bridge; revision back to 3,
  water tris back to baseline 37,374).

Delivered on device (code 49, `org.hearthvale.game.test.m2night`, upgrade install —
saves preserved, same debug keystore): v49 + the water-mode exit fix (B now cancels
the water placement when not stroking; dpad/mode-switch/view/height buttons are no
longer swallowed and pass through to the parent handlers that re-select terrain
tools) + cottage
half-scale brick art pass + world-diagonal viewer radius + `HARNESS_BRIDGE_TIMEOUT`.
If the B button or water painting feels off again, `am force-stop` then relaunch.

## 2026-09-20 — flower arch grown 2x to street scale (v51 in flight)

The on-device arch from the previous rebuild was already 60 x 72 x 36 cells
(3.75 x 4.5 x 2.25 m, 18,663 voxels) — but the user reports it still reads
small against the street space it spans. Grew the *approved* design 2x linear
with `tools/magicavoxel/scale_arch.py` (deterministic 2x2x2 supersample of the
canonical .vox; palette verbatim, no voxel moved/recoloured):
120 x 144 x 72 cells = 7.5 x 9 x 4.5 m, 149,304 voxels. Greedy mesh unchanged
at 2,058 triangles / 9 surfaces / 4,002 verts (2x scale only doubles merged
rectangle sizes), so no perf impact is expected.
`m2_table_assets.gd` VOXEL_COUNTS updated to 149304; README documents the
supersample. Tests: magicavoxel_asset_test 141/141, m2_furniture_placement_test
29/29. Pushed as `0155730`.

Note: an MCP "big_v2" rebuild (52 x 57 x 44) was started in staging against
stale 2.3 x 3 x 0.56 m size data before the current canonical dimensions were
checked; it is smaller than the existing arch and was discarded (staging
files deleted). The 2x supersample of the approved source is the current
approach.

Device state when v51 lands: `192.168.1.15:38865`, package
`org.hearthvale.game.test.m2night`, upgrading code 50 -> 51 in place (same
debug keystore, saves preserved). Water-mode B-exit fix (efa5af2) is on main
and in every build since v49.
