# M2-06 — Roads & Paths vertical slice

**Status:** painted-region path system active on `feat/m2-path-ground-polish`; terrain-cut packed earth, safe restoration, brush sizing, erase mode, and first visual-polish pass are implemented.

## Player-facing result

The Build Catalogue opens **Roads & paths** with packed earth, cobblestone, stepping stones, and the existing bridge entries. Choosing a path style enters a continuous terrain paint tool rather than the retired point/polyline workflow.

Current controller grammar while a path tool is active:

- hold A — paint continuously; release A commits one stroke;
- X — toggle paint / erase mode;
- D-pad left/right — shrink / grow the brush;
- left-stick click precision mode — changes brush sizing from 0.25 m steps to 0.125 m steps;
- B — cancel a live stroke, or close the path tool while idle;
- LB — undo the latest committed stroke;
- right stick — orbit; LT/RT — zoom.

A live stroke is preview-only. Commit performs a second stale-world check before changing authority or terrain. Pause, focus loss, disconnect, cancellation, and stale-revision rejection cannot silently commit a path.

## Authoritative contract

Paths are painted **structural-grid regions** on the 0.125 m world grid. Saved path records contain a stable ID, a style ID, and owned cells; committed path authority contains no centreline, polyline points, or saved width.

One painted cell belongs to at most one path style. Painting another style transfers ownership of overlapping cells. The latest paint wins. The global path-cell budget remains bounded by validation.

Brush width is interaction state only. It rasterizes circular brush stamps and swept strokes into authoritative cells. This permits tiny trails, ordinary roads, irregular courts, and broad town-square regions without inventing a centreline.

## Packed-earth terrain profile

Packed earth modifies native terrain. Depth is derived from distance to the **edge of the painted region**, not distance to a centreline:

- edge ring — lawn grade, 0 voxels removed;
- first interior rings — 1 structural voxel removed;
- sufficiently broad interior — 2 structural voxels removed.

The result is a stepped U-shaped cross-section with a level shoulder and a lowered packed centre. Broad plazas therefore develop a broad lowered centre rather than a bowl.

Terrain edits use exact native voxel before/after values and participate in the same user-visible path history transaction as the painted authority.

## Terrain ownership and restoration

Every voxel removed by packed earth is recorded as path-owned terrain with its original material. The ownership data is saved with the world.

When packed earth is erased or painted over by another material, only voxels still owned by the path system are restored. If a voxel has been independently changed after the path acquired it, restoration preserves that newer edit rather than overwriting it.

Undo/redo restores both path authority and matching terrain ownership. Save/reload preserves the relationship between painted packed-earth cells and their excavated native terrain.

## Presentation

Saved authority remains on the 0.125 m structural grid. Packed-earth presentation may use the supported 0.0625 m detail grid.

The current polish pass replaces the old solid brown cell boxes with deterministic half-cell wear patches. Lawn-grade shoulders deliberately break back into grass while lowered interior cells remain visually continuous. Packed-earth colour variation stays inside the existing two-material surface budget.

Cobblestone and stepping-stone presentation still derive entirely from painted area masks and remain disposable rendering rather than authority.

## Verification

Current local path suite after erase-mode integration:

- `tests/m2_painted_path_region_test.gd`: 22 checks, 0 failures;
- `tests/m2_painted_path_authority_test.gd`: 28 checks, 0 failures;
- `tests/m2_path_terrain_excavation_test.gd`: 16 checks, 0 failures;
- `tests/m2_path_placement_test.gd`: 52 checks, 0 failures;
- `tests/m2_path_render_test.gd`: 35 checks, 0 failures.

The placement coverage includes continuous hold-to-paint, brush sizing, live-stroke size lock, terrain excavation, terrain ownership, save/reload, material overwrite, direct erase, player-facing X-toggle erase strokes, and atomic undo.

GitHub `cottage-paths` passed for the preceding polish commit `aedd32f80420109e6a8dcb9d6233b050af8d9b19`. The erase-mode commit is checked independently by the normal path CI shard.

## Remaining polish

The structural and terrain-safety contract is in place. Remaining work is primarily presentation and feel: richer packed-earth edge/grass contact, small stones and wear variation, further batching/mesh reduction where it improves Mobile cost, and physical-device visual approval.
