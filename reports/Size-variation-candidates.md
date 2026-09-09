# Compact trees and flat mushroom review candidates

The approved three tree silhouettes now have one compact companion each, and the
woodland set has two additional low mushroom patches. All five are standalone
review candidates. Existing tree and mushroom sources, gameplay vegetation,
placement records and saves remain unchanged.

| Candidate | Triangles | Bounds size | Relative tree size |
| --- | ---: | --- | --- |
| Compact orchard | 1,696 | 3.625 × 4 × 2.125 | about 80% of orchard |
| Young riverside | 1,128 | 2.125 × 4.875 × 1.625 | about 80% of riverside |
| Low wind-shaped | 1,448 | 3.75 × 4.125 × 1.875 | about 80% of wind-shaped |
| Flat mushroom trio | 178 | 1.5 × 0.5 × 1 | static |
| Wide flat mushroom scatter | 222 | 2 × 0.5 × 1.375 | static |

The registered `hearthvale-magicavoxel` server created every source in ignored
staging. `assets/source/magicavoxel/size-variations.authoring.json` records the
MCP copy, voxel resampling, palette, explicit volume correction, box modelling
and snapshot operations. The initial compact-tree blockouts exposed an important
pipeline issue: 0.8 resampling produced odd horizontal VOX dimensions. Centering
an odd source volume places faces on half cells, and the bake snap collapsed a few
triangles. Those blockouts were rejected. Through MCP, each voxel result was
unioned into a new even-width/even-depth declared volume before promotion. The
final candidates pass exact grid, cubic-face, pivot and bounds checks.

Canonical `.vox` files live in `assets/source/magicavoxel`; matching OBJ, MTL,
provenance `.asset.json` receipts and baked `.res` meshes are under
`assets/models/magicavoxel`. Greedy meshing preserves exact same-palette exposed
face coverage. All rest vertices remain on the 0.125 grid and all connected
components reach Y=0. Original tree hashes and baked bounds are pinned in the
new validation so this pass proves the approved sources were not modified.

The compact trees use the same gentle 12-second affine wind motion with independent
phases. Roots remain fixed and mesh seams stay coincident. Both mushroom patches
remain static and retain ordinary matte materials. No runtime integration occurs.

Open `scenes/size_variations_preview.tscn`. Approved full-size trees stand behind
their new compact counterparts; both flat mushroom patches sit in front. Space
pauses, W toggles wind and Escape closes.

Evidence:

- `screenshots/size-variations-comparison.png`: labelled actual Mobile comparison.
- `screenshots/size-variations-preview.gif` / `.mp4`: 1280×720, 288 frames at
  24fps, seamless 12-second loop.
- `logs/size-variations-asset.log`: 104 passing source provenance, original
  immutability, grid, cubic geometry, pivot, bounds, compact-ratio, palette,
  material and triangle-budget checks.
- `logs/size-variations-meshing.log`: exact exposed-face coverage and rooted
  component validation for all 20 authored candidate sources.
- `logs/size-variations-mobile.log`: 40 passing actual Vulkan Mobile checks on
  RTX 3070, including GPU/CPU deformation and normal parity, pause/off behavior,
  static mushrooms and source-mesh immutability.
- `logs/size-variations-check-suite.log`: full normal `tools/check.ps1` suite
  passes with exit 0 and `check ok`, including 104 asset checks, 31 headless
  size-variation wind/static checks and the expanded 20-source converter gate.

The bounded independent review found no implementation defect. It suggested
explicit original immutability coverage; source hashes and baked AABBs were then
pinned and the asset gate increased from 98 to 104 passing checks. Visual approval
and physical Thor performance remain open; desktop Mobile is not handheld evidence.
