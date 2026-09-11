# Stepping-stone visibility: native-height audit and inward faces

2026-09-11, `feat/m2-path-ground-polish`.

## Request and finding

The player reports stones visible below the ground only while digging and disappearing on release. Investigate the surface reference before attempting terrain cutouts or more vertical offsets.

The native terrain is a scaled VoxelTerrain using blocky cube models. Path visuals and the backend share their world coordinate frame. In the real scene, the path's column scan agrees with the existing `TerrainBackend.sample_surface_plane()` API: 243 sampled top positions, zero mismatches and maximum height difference 0.0, both before and after a committed dig. The tested stone top centres are 0.00399971008300781 world units above that surface. This does not substantiate the earlier claim of a multi-voxel placement-height error.

The concrete defect is `_append_rounded_stone()` emitting inward triangle winding. Godot uses clockwise front faces; supplied outward normals affect lighting but do not repair culling. All 216 top, 216 bottom and 432 side triangles in the actual stepping path fail the winding check. The visible buried underside and inside sidewalls explain the misleading holes/rims. Live sculpt does not refresh the path until the backend change event on release; the dig regression verifies that behavior without changing it.

## Reproduction before the correction

Diagnostic-only commit: `932cbf5d52d8ed0ae7d4f1a818f9ebede8be966a` (runtime identical to `4ec32a83fd5556c39fe967c1f62419f0bb502eb3`).

GitHub Actions run: `34655099886`.

- Native path test: 49 checks, 6 failures, exclusively the top/bottom/side winding assertions before and after digging.
- Actual Forward Mobile/D3D12 path test: 55 checks, the same 6 failures, all 3 captures retained.
- Artifact: `cottage-paths-932cbf5d52d8ed0ae7d4f1a818f9ebede8be966a`, ID `10285450237`.
- Images: `reports/screenshots/m2-paths/all-styles.png`, `stepping-close.png`, `stepping-reverse.png`.
- The two close views use the same runtime path batch, native terrain, materials and lights as the overview. No substitute raised fixture or ground mesh.

## Correction and scope

Reverse the triangle indices of the rounded stone top fan, bottom fan and side quads. Keep the existing outward lighting normals and back-face culling. No vertex-position, terrain-height, thickness, footprint, spacing, colour, material, save, terrain-authority, editing or performance changes. Packed-earth/cobblestone box geometry is untouched. No socket mask or contact skirt is introduced.

The expanded normal path test retains existing assertions and additionally verifies winding, native surface parity, the live-dig/cancel/release/undo sequence and unchanged saved paths. Re-run the normal exact-head native/Mobile/export jobs after this correction; the diagnostic run above is deliberately red and is not a fixed-build receipt.

## Verification boundaries

Pinned editor: Godot 4.7.2.stable.official.ed1daf0bf. Native terrain grid: 0.125. Actual Mobile evidence here is Windows D3D12 using Microsoft Basic Render Driver, not physical Thor evidence. Local analysis checked triangle orientation; local Godot execution was unavailable. Physical Thor acceptance remains with the player.

Existing CI blocker: the performance guard introduced by the earlier CI transplant cannot load `tests/performance/m2_mobile_performance_baseline.json`. Previous run `34652687573`, section-commit job `103438219045`, fails before any performance scenario. This is not a measured section-placement slowdown. Preserve those gates and do not bypass gated Drive delivery; repair this separate CI dependency in its own scope.
