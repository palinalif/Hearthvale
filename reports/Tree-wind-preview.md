# Gentle tree wind preview

The player authorized a render-only off-grid animation trial after approving
the three MCP tree candidates. This is a standalone wind study; gameplay trees,
rest meshes, VOX sources, palette receipts, placement records and saves are not
modified by the animation.

Open `scenes/tree_wind_preview.tscn` in pinned Godot 4.7.2, or run:

```powershell
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . --scene res://scenes/tree_wind_preview.tscn
```

Space pauses, W switches wind off/on, and Escape closes the preview. It uses
its own explicitly advanced clock, so pause freezes both position and lighting.

## Motion and geometry

`scripts/tree_wind.gd` applies `shaders/tree_wind.gdshader` through per-surface
material overrides. All four palette groups on a tree receive exactly the same
deformation. Three slow harmonics form a seamless 12-second cycle; each tree has
a different phase. The default maximum X crown displacement is 0.16 world units
(about 1.3 structural cells), with a smaller Z component. The base at Y=0 stays
exactly fixed, and motion increases linearly with height. Upper root-flare
vertices move slightly; their ground contacts do not move.

This first trial uses a gentle affine shear instead of independent branch or
leaf flutter. It keeps every original plane planar and every point on a shared
edge coincident, including T junctions from greedy meshing. It requires no mesh
subdivision, skeleton, additional geometry or altered source files. A matching
inverse-transpose normal transform keeps lighting consistent. Shadows use the
same shader deformation. Bounds are expanded for the maximum allowed strength.

The authored 0.125 rest grid remains intact. The player's animation exception
allows the temporary visible deformation; it does not authorize a different
structural grid or changes to simulation/placement geometry.

## Evidence

- Headless wind test: 21 checks passed for ground anchors, maximum bounds,
  shared-edge interpolation, unchanged rest grid, loop continuity, independent
  phases, pause, wind-off and source resource preservation.
- Actual Mobile wind test: 30 checks passed, including reference-render parity
  at three times, visible image changes, original appearance with wind off,
  pixel-identical paused frames and a complete 288-frame capture.
- Actual renderer: Vulkan / Forward Mobile on NVIDIA RTX 3070, Godot
  4.7.2.stable.official.ed1daf0bf. These are desktop results, not Thor measurements.
- One bounded independent Luna/low shader/controller/test review found no
  actionable implementation defects. The noted headless limitation is covered
  by the separate actual Mobile run.
- `tools/check.ps1` includes the new wind gate and passed (exit 0, `check ok`),
  including the existing 112-check acceptance write and 8-check cold read.

The render test independently transforms vertices and normals on the CPU,
renders those with the original materials, and compares them to the GPU shader
output. This tests geometry, normals and shadows together. Raw frames stay in
ignored `.tools/tree-wind/frames`; logs are `reports/logs/tree-wind-*.log`.

The 12-second preview is `reports/screenshots/tree-wind-preview.mp4` (24 fps)
and `tree-wind-preview.gif` (16 fps). The MP4 preserves more detail. Both are
encoded from actual Mobile screenshots, not synthetic animation.

## Remaining review

Judge the strength and pacing in motion. This trial does not include independent
branches, leaf flutter, collision animation, gameplay integration or a dense
grove/Thor performance benchmark. Integration would need to carry the pause,
instance-phase and expanded-bounds behavior into the vegetation presentation
path; it must leave authoritative planting and saves unchanged.
