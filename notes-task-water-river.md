# Water / River — branch progress (task/water-river)

**STATUS: all slices delivered. Full verified Drive-delivery CI is green
(run 35184766877, 30/30 jobs, ARM64 `build-thor-apk` succeeded). Ready to merge.**


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
