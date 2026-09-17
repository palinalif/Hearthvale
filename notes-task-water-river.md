# Water / River — branch progress (task/water-river)

**STATUS: waterfall/animation slices were green; the premade-river → region unification is
in progress (import-safe compromise landed in `cee413c`; awaiting a green Drive-delivery run).
See the Known issues / TODO below for the headless-import fragility that shaped it.**


Carved from `main @ c2364ef`. User-approved feature: **editable water** per `docs/design.md`
— streams (editable centreline + width/bed depth/surface height/flow direction), lakes
(bounded region + level), waterfalls (join regions), river tool previews carved bed+banks,
commit as terrain+water in one undoable op. Water is an **editable scenery layer, not a
general fluid simulation**; no auto-flooding.

## Delivered + locally verified (headless, deterministic)

| Slice | Scope | Tests |
|---|---|---|
| 1 | Authoritative `water` record collection in `LandscapeState` (add/erase/document/validate/restore; limits, grid snap, render-cell budget; backward-compatible) | `water_region_test` 42/0 |
| 2 | Pure region geometry — containment (polygon / stroke), surface level, `is_submerged`, flow, structural-cell footprints (lake rasterise, stream stroke) | (in 42/0) |
| 3 | Presentation water surface — clipped to terrain (only below-level cells) + region bounds; one animated ShaderMaterial per region; hooked into `m1_scene` at every record apply/reset/undo/redo/load | `water_visual_test` 8/0 |
| 4a | Pure carve plan for the river/lake tool preview — bed (per-type depth) + bank shore ring; deterministic | `water_carve_plan_test` 12/0 |

All green locally: import clean; `water_region_test` 42/0, `water_visual_test` 8/0,
`water_carve_plan_test` 12/0; `m2_path_state_test` 21/0, `m2_bridge_state_test` 15/0.

## Files
- `scripts/landscape_state.gd` — `water` records (WATER_* limits; `add_water`/`erase_water`;
  `_validate_water_record`, `_estimated_water_render_cells`, `_water_points/flow/polygon_area/polyline_length`).
- `scripts/water_region_geometry.gd` — pure geometry over a region record.
- `scripts/water_visual.gd` + `shaders/water_surface.gdshader` — clipped animated surface (presentation only).
- `scripts/water_carve_plan.gd` — pure bed/bank preview plan.
- `scripts/m1_scene.gd` — `water_visual` created/attached/refreshed + `_sync_water_visual()` at record sites.
- `tests/water_region_test.gd`, `tests/water_visual_test.gd`, `tests/water_carve_plan_test.gd`.

## Region record shape
`{"id":int, "type":"lake"|"stream", "level":float, "points":[[x,z],...],
  ["width":float, "flow":[dx,dz] (stream only)]}`. Level + points + width snapped to
`Grid.UNIT` (0.125). Lakes are closed boundary polygons (≥3 pts); streams are centreline
(≥2 pts) + width + unit flow.

## Not run locally (CI-gated / environmental)
- Native voxel legs (native carve, live-scene render) — no native module locally; same baseline
  as grass_tone. `m2_starter_scene_test` / `m2_starter_valley_test` fail locally only on
  "Native VoxelBuffer unavailable" (environmental, unchanged on main).
- `m1_landscape_test` 1/1 fixture (`user://`) — identical on plain main (not a regression).

## Delivered: slice 4b — interactive river/lake controller tool + undo integration
`scripts/m2_scene_water.gd` (new head; `m1.tscn` points at it) + `scripts/water_terrain_excavation.gd`
(carve planner, `water_excavation_test` 8/0). Wired into the build browser's Paths & bridges tab
as `water` kind (stream/lake entries). Follows the proven path-tool pattern:
- **Stream**: hold A to drag a centreline; width fixed 1.5; level = terrain surface at the stroke
  start; flow = stroke direction. Release A commits.
- **Lake**: press A to outline a boundary polygon; near the first point closes it; level = highest
  terrain inside the region. B removes the last vertex.
- Preview renders the water surface live via `water_visual` as it is drawn.
- Commit records the region **and** carves its bed/banks (`WaterExcavation`) as ONE landscape undo
  transaction; on any failure the record/terrain are restored. Cancel restores the baseline.
  Menus block the tool; disconnect/focus loss stops a held stroke via the shared cancel path.

CI fixes applied for the established contract:
- `document()` omits the `water` key when empty, so water-free saves keep an identical schema
  (planter save-authority-neutral + legacy-restore guards restored).
- Water tools live in the existing Paths & bridges tab (no 4th category); the two placement
  regressions count that tab's cards (5 -> 7).

**Remaining: a visual playtest on the Thor** (native carve look, stream/lake feel, water-surface
render in game) — visual approval belongs to the user.

---

## Waterfall (derived cascade) — delivered, CI green

A waterfall is a **derived presentation**, not a new water type and not a fluid sim: a higher
authored body overhanging a lower one renders a falling curtain + base splash (design line 152:
"a waterfall joins authored upper and lower water regions").

- `scripts/waterfall_geometry.gd` (new, pure + rect-scoped): `derive()` scans each upper body's
  edge (authored corners + midpoints) for a crown whose terrain is near/under the upper level and
  whose base is a distinct lower body; snap to the structural 0.125 grid, head 1..12 m, deduped
  per crown, keyed `"<upper>:<lower>"`.
- `LandscapeState.waterfall_suppressions` — the **only** stored waterfall state (a dismissed
  upper/lower pair). `document()` omits the key when empty (schema-neutral); capped at 64;
  `suppress_waterfall`/`unsuppress_waterfall`.
- `water_visual.gd`: `refresh_waterfalls(dirty_rect)` re-derives only a terrain edit-bounds grown
  by `SAMPLE_MARGIN` (never the whole map) and builds the cascade (curtain + splash,
  `shaders/waterfall_fall.gdshader`). `active_waterfalls()` exposes crowns to the tool.
- Scene wiring (`m1_scene.gd`): re-derives on terrain change (edit-bounds), water commit/undo/redo,
  and load; `_sync_water_visual` re-applies suppressions.
- Interaction (`m2_scene_water.gd`): in the water tool, aiming at a visible fall and pressing A
  dismisses it as one landscape undo transaction.

Tests (now in `tools/check.ps1` — the water tests were previously local-only): waterfall 19,
waterfall_visual 6, water_region 54 (incl. suppressions round-trip), carve 12, water_visual 8,
excavation 8 — all 0. Pushed `9651a1a`; CI run 35193493385 **30/30 green, overall success**
incl. `build-thor-apk` (verified ARM64 APK) + Windows playtest. PR #27 OPEN/MERGEABLE.

**Remaining: visual playtest on the Thor** — waterfall cascade/splash look, dismissal feel; visual
approval belongs to the user.

## Waterfall animation + particles — delivered, CI green

On top of the animated shader curtain (downward-scrolling streaks + base foam), each derived
fall now carries the **particle aspect** (`water_visual.gd`, `GPUParticles3D` billboard emitters,
sized to the fall width):
- **Spray** — a short-lived bed of droplets at the pool, thrown up and out (spread 34°, gravity
  9.8), no prewarm so it reads as fresh splashes.
- **Mist** — a prewarmed (`preprocess` = full lifetime) bed of large, faint billboards that drift
  up slowly; hazy base with no pop-in.

Notes: spatial shaders use ALPHA for transparency (no `alpha_blend` render mode); GPUParticles3D
`prewarm` is read-only — set `preprocess` (duration); the draw pass is a `QuadMesh` carrying the
billboard material (`draw_pass_1`), sized by the particle `scale_min/scale_max`.

Headless waterfall_visual 7/0 (asserts both emitters per fall). Pushed `ffefdc7`; CI
35196625269 **30/30 green, overall success** (incl. verified ARM64 APK + Windows playtest).
**Remaining: visual playtest on the Thor** — spray/mist density, cascade look; approval is the user's.

## Premade river → region unification — import-safe compromise

The starter river was a bespoke static mesh (`M1Scene.river_water`) that never became a water
region, so it diverged from player-authored water (rendered via `M1WaterVisual`). `PremadeRiver`
(`scripts/premade_river.gd`) derives it as a deterministic stream region; `M1Scene._ensure_premade_river()`
adds it once (idempotent, covers fresh + existing worlds). The legacy mesh is kept **hidden**
(`river_water.visible = false`) because removing it is blocked by the import fragility below.
`premade_river_test` 15/0.

## Known issues / TODO

### TODO: make the headless import less fragile (deep `extends` chain)
The headless `godot --headless --import` gate fails if the **base** `scripts/m1_scene.gd` is
*shrunk* (even removing one function): the deep scene `extends` chain
(`m2_scene_water → m2_scene_starter_valley → m2_scene_style_preview_stability →
m2_scene_path_erase → m2_scene_path_terrain_ownership → … → m1_scene`) fails to resolve —
"Could not resolve class `m2_scene_starter_valley.gd`" at `m2_scene_water.gd:1`. Import exits 0,
but `tools/test-m1-placement.ps1` `Assert-GateOutput` fails on any `SCRIPT ERROR|ERROR:|Parse
Error|FAIL:` in the output.

- **Reproduced** on `f0429e1` with no other changes: delete `_build_river_water_mesh()` from
  `m1_scene.gd` → clean `.godot` `--import` emits the parse error.
- **Adding** to `m1_scene.gd` is safe; **removing** is not. New files + editing the non-base
  scenes are safe. So the chain is effectively frozen against shrinking its base.
- **Fix-forward:** break the 6+ level `extends` stack (compose off one common base, or delegate)
  so import order no longer depends on the base script's size; then the now-dead `river_water`
  mesh and its three functions can be deleted for a clean unification.

(Found while doing the river → region unification.)

## Water tool consolidation (stream + lake → one terrain "Water" tool)
- **User directive:** remove the separate Stream/Lake catalogue entries + the water
  catalogue panel; make water a single **Water** terrain tool (like raise/dig), paint
  stroke-based (cells under the brush), **auto-derived level** (snaps to terrain at the
  stroke start), and it must support **connecting different water levels** (the existing
  waterfall derivation handles this — a carved cliff between an upper and lower body
  yields a derived cascade).
- **Implementation (reuses the existing, playtested stream machinery):**
  - `m1_scene_tool_ui.gd`: `"water"` added to TERRAIN_TOOLS (between slope and foliage);
    routed as a non-sculpt tool (like foliage/tree); radius setting stays (it now sets
    the river width), other settings disabled for it.
  - `m2_scene_water.gd`: removed the water catalogue (`_build_water_catalogue`,
    `_open/_close_water_catalogue`, `_choose_water_kind`, the panel/buttons, the browser
    `water_stream`/`water_lake` entries, the HUD catalogue branch). `_select_terrain_tool`
    now activates/deactivates the paint (`water_placement_active`); brush radius sets the
    stream width (`2.0 * brush_radius`, min 0.5); B cancels a stroke without deactivating
    the tool; pause stops the stroke; auto level via `_terrain_top` at stroke start.
  - `m2_scene_build_browser.gd`: removed the now-dead water catalogue thumbnail model.
- **The paint produces a stream-type region** (centreline = stroke path, width = brush
  diameter, level = auto, flow = stroke direction) — a narrow brush reads as a stream,
  a wide one as a river. Region records, carve plan, clipped surface visual, and the
  waterfall derivation are all unchanged.
- **Verified:** tool_ui + water + build_browser import clean; scene instantiates + the
  Water tool activates/deactivates the paint (water_active=true→false on tool switch);
  water machinery tests green (region 54, visual 8, waterfall 19, carve 12). The
  m2_build_browser test's "native browser scene ready" failure is a **pre-existing
  headless limitation** (`_player_restored` never completes in headless — confirmed by
  stashing all my changes and reproducing it on the baseline), not a regression.
- **Not yet:** on-Thor playtest of the new Water tool (user approval), CI run.
