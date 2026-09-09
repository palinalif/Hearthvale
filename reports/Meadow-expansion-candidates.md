# Three additional plants and three rocks

Six project-authored review candidates extend the approved foliage direction.
They were created and edited through the registered `hearthvale-magicavoxel`
server, with blockout/review snapshots from six directions for each source.
`assets/source/magicavoxel/meadow-expansion.authoring.json` records every authoring
operation. Raw snapshots and MCP output remain in ignored `.tools/magicavoxel`.

| Source stem (after `hearthvale_`) | Triangles | Bounds size | Character |
| --- | ---: | --- | --- |
| foliage_seedgrass | 168 | 0.875 × 1 × 0.75 | Three staggered tan seed heads and sparse leaves |
| foliage_cream | 212 | 0.875 × 0.5 × 0.875 | Low cream blooms with inset warm centres |
| foliage_mauve | 208 | 1 × 1 × 0.75 | Uneven muted mauve flower spikes |
| rock_slab | 120 | 1.375 × 0.5 × 0.75 | Broad, chipped, low stone |
| rock_split | 154 | 1.375 × 0.75 × 0.75 | Two unequal shoulders with an open upper cleft |
| rock_moss | 142 | 1.375 × 0.625 × 0.75 | Small connected outcrop and restrained moss patches |

The `.vox` sources are in `assets/source/magicavoxel`; matching `.obj`, `.mtl`,
`.asset.json` provenance receipts and baked `.res` meshes are in
`assets/models/magicavoxel`. All retain the 0.125 rest grid and ground-centred
source-volume pivot. Coplanar same-palette merging removes internal/duplicate
faces without changing the source silhouette. Bake restores exact grid points
and matte nonmetallic materials. No existing source or gameplay asset is replaced.

The plants reuse the approved affine wind shader, with independent phases and
strengths 0.040 / 0.020 / 0.035. Roots remain fixed. Rocks use static standard
materials, including their moss; no wind is applied to them. This introduces no
new simulation, save data, collision or runtime catalogue integration.

Open `scenes/meadow_expansion_preview.tscn` for the labelled six-candidate view.
Use `-- --context` for the same assets beneath the trees at true scale.
Space pauses, W toggles wind, Escape closes. The preview spacing was adjusted
after the first Mobile capture so seed heads and rock labels remain separated.

Evidence files:

- `screenshots/meadow-expansion-preview.png`, `.gif`, `.mp4`: labelled close view.
- `screenshots/meadow-expansion-context.gif`, `.mp4`: tree-scale wind loop.
- `logs/meadow-expansion-asset.log`: 117 passing import, grid, palette, pivot,
  source-hash, bounds and triangle-budget checks. Every asset is below 500 triangles.
- `logs/meadow-expansion-meshing.log`: exact exposed-face coverage and grounded
  connected components for all 12 candidate sources. This Python regression is
  now a bounded part of `tools/check.ps1` as `check-candidate-meshing.log`.
- `logs/meadow-expansion-mobile.log` and `logs/meadow-expansion-context-mobile.log`:
  44 checks passed in each actual Vulkan Mobile run on RTX 3070, GPU/CPU deformation and normal
  comparisons, pause/off checks and explicit static-rock/material checks.
- `logs/meadow-expansion-wind-headless.log`: 35 passing headless wind/static-rock checks.
- `logs/meadow-expansion-check-suite.log`: the normal full regression was attempted
  but stopped at import. Separately modified `scripts/m1_garden_visual.gd:38–42`
  references undeclared `kind` and `variant`, cascading into scene parse errors.
  That gameplay change is outside this asset pass and was left untouched.
- `logs/meadow-expansion-check-suite-rerun.log`: after the independent parse fix,
  the full rerun reached `visual-grid` and stopped on the concurrent gameplay wind
  integration calling `set_surface_override_material` on `MultiMeshInstance3D`
  (`TreeWind._init`, through `M1GardenVisual.apply_records`). The failure is preserved
  in `logs/meadow-expansion-shared-wind-failure.log`. The standalone candidate
  previews use MeshInstance3D and pass their checks. The full suite is **not passing**
  for this shared-workspace state; rerun after that independent integration is fixed.
  No failing gate was bypassed and that gameplay work was left untouched.

The bounded independent review identified the missing converter-suite invocation;
it was added with a timeout and propagated nonzero exit status. No gameplay
implementation changes were needed. Player visual review and physical Thor
performance remain open. Desktop Mobile captures are not handheld measurements.
Both MP4 loops are 1280×720, 288 frames at 24 fps (12 seconds), with GIF previews.
