# Woodland and riverside review candidates

The user approved making reeds, ferns and mushrooms after the meadow additions.
These three new sources were authored and edited through the registered
`hearthvale-magicavoxel` server. They remain standalone review candidates; this
pass does not add them to gameplay or replace any previous assets.

| Asset | Triangles | Bounds size | Motion |
| --- | ---: | --- | --- |
| River reeds | 212 | 1.125 × 1.625 × 0.75 | Gentle sway, strength 0.055 |
| Woodland fern | 274 | 1.25 × 0.625 × 1.125 | Smaller sway, strength 0.025 |
| Little mushrooms | 182 | 0.875 × 0.5 × 0.875 | Static |

Source files are `assets/source/magicavoxel/hearthvale_foliage_reeds.vox`,
`hearthvale_foliage_fern.vox`, and `hearthvale_foliage_mushrooms.vox`.
Matching OBJ, MTL, provenance `.asset.json` and baked Godot `.res` files live in
`assets/models/magicavoxel`. `woodland-candidates.authoring.json` retains all 91
MCP operations, including palette setup, box authoring, subtractive edits and
snapshots. Raw output remains in ignored `.tools/magicavoxel` staging.

Each source preserves the 0.125 structural grid and declared-volume centred
ground pivot. All connected components reach Y=0. The fern has staggered lateral
leaflets; reeds have tall narrow stems and differently sized brown heads;
mushrooms have cream stems and warm, stepped caps. The first Mobile review showed
overly pointed mushroom caps, so an MCP refinement lowered the tops into broader
caps. Camera framing was adjusted to leave space above the reeds.

The shared affine wind shader keeps roots fixed and greedy mesh edges coincident.
Only reeds and ferns receive wind controllers. Mushrooms, including context
instances, retain static standard materials. Source geometry and saved data do
not animate. The shared wind test now handles the actual animated instance count
instead of assuming three, preserving coverage for all earlier previews.

Open `scenes/woodland_preview.tscn`; add `-- --context` for tree-scale context.
Space pauses, W toggles wind, Escape closes.

Evidence:

- `screenshots/woodland-preview.png`, `.gif`, `.mp4`: labelled close view.
- `screenshots/woodland-context.gif`, `.mp4`: tree-scale 12-second loop.
- `logs/woodland-asset.log`: 54 passing grid, pivot, bounds, source hash, pinned
  pipeline, palette, matte material and triangle-budget checks.
- `logs/woodland-meshing.log`: exact exposed-face coverage and rooted-component
  checks pass for all 15 candidate sources.
- `logs/woodland-mobile.log` and `logs/woodland-context-mobile.log`: 29 checks pass
  in each actual Vulkan Mobile run on RTX 3070, including GPU/CPU deformation and
  normal parity, pause/off appearance and explicit static-mushroom checks.
- `logs/woodland-check-suite.log`: the full normal `tools/check.ps1` suite passes
  with exit 0 and `check ok`, including all prior asset/wind previews, the 15-source
  converter regression and 20 headless woodland wind/static checks. The shared
  workspace failures seen during the previous asset pass did not recur here.

Both MP4s are 1280×720, 288 frames at 24fps, for a seamless 12-second loop.

The bounded independent review found no actionable defect in the preview,
variable-instance wind validation, asset checks or normal-suite registration.
Visual approval and physical Thor performance remain open. Desktop Mobile
rendering is not a handheld measurement.
