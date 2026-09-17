# Water / River — branch progress (task/water-river)

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

## Remaining: slice 4b — interactive river/lake controller tool + undo integration
Follows the proven path-tool pattern (`m2_scene_paths.gd`): `_begin_*_placement` (guarded) →
A starts a stroke → `_sample_*` into the stroke → `_update_*_preview` (render via
`WaterCarvePlan` + `water_visual`) → release A commits (terrain carve + `add_water` as **one**
landscape undo transaction via `landscape_state.document()` snapshot) → cancel restores the
snapshot. Native terrain carve is CI-gated.

**UX decision needed (visual/interaction approval is the user's):**
1. **Stream** — drag a centreline; width by a held modifier/step; level by a control (bed auto-
   carved to `level - 0.4`). Flow direction = stroke direction.
2. **Lake** — outline a boundary polygon (or a bounded area brush), then set the level.
3. Preview shows carved bed + banks + the water surface before commit; release commits.

Needs CI (native carve + ARM64 APK) + a visual playtest on the Thor before it counts as delivered.
