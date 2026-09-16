# MagicaVoxel source assets

These `.vox` files are project-authored sources produced through the pinned
`Mahinika/magicavoxel-mcp` development server. The server is not shipped with
the game. Approved sources are converted by `tools/magicavoxel/vox_to_obj.py`;
generated OBJ, MTL, baked RES, and `.asset.json` receipts live under
`assets/models/magicavoxel`.

Authoring convention: terrain/structural sources use `0.125`; non-terrain
presentation sources such as trees, foliage, mushrooms, flowers, and rocks use
`0.0625`. MCP Y maps to Godot Y. Keep pivots at the horizontal centre of the declared VOX dimensions
and the model base at Y=0. The converter removes hidden faces and preserves one
surface material per used palette index. Candidate assets must pass
`tests/magicavoxel_asset_test.gd` and an actual Mobile render before runtime use.

Godot's OBJ importer applies tiny compression drift, so
`tools/magicavoxel/bake_mesh.gd` snaps the imported mesh back to the explicit
declared tier and saves the runtime `.res`; gameplay loads that baked resource.

The MCP writes only to the ignored `.tools/magicavoxel` staging directory.
Promote a reviewed source explicitly; never point the server at this canonical
directory.

## Tree review candidates (baseline d2535ed)

`hearthvale_tree_orchard.vox`, `hearthvale_tree_riverside.vox`, and
`hearthvale_tree_wind.vox` are review-only alternatives to procedural variants
0, 1, and 2. Gameplay still uses `VegetationMesh`. The pilot is retained.
`tree-candidates.authoring.json` records the actual registered MCP operations:
box modelling, subtractive edge cuts, small stepped extensions, and six
snapshot passes per candidate. The user rejected the initial chunky shelf pass;
the final sources use 22/16/20 smaller overlapping sprays, then tapered bent
trunks, fine forks and small root flares in response to trunk feedback. Raw MCP snapshots
and rejected models remain in ignored staging.
The orchard has an additional top-variation pass recorded in
`orchard-top-variation.authoring.json`: lowered caps, broad low shoulders and
a taller off-centre tip. Its trunk and the other two sources are unchanged.

Rebuild each candidate source with `vox_to_obj.py --greedy`, run the pinned Godot headless editor
import, then run `bake_mesh.gd -- SOURCE.obj OUTPUT.res`. Baking preserves the
palette and enforces matte, nonmetallic bark/foliage; Godot's legacy OBJ material
import can otherwise produce metallic=0.999 from this MTL. The old pilot has
not been rebaked or replaced by this candidate pass.
The opt-in greedy pass merges only coplanar faces within a palette group.
`python tests/magicavoxel_converter_test.py` checks exact exposed-cell coverage
for all three sources. The default converter still reproduces the pilot OBJ
byte for byte.

Run `tests/magicavoxel_asset_test.gd` headlessly, or with the actual Mobile
renderer and `-- --require-rendering --capture=res://reports/screenshots/tree-candidates.png`.
This writes one labelled procedural/candidate comparison per variant.
See `reports/MagicaVoxel-tree-candidates.md` for review evidence and concerns.

## Ground foliage review set

`hearthvale_foliage_grass.vox`, `hearthvale_foliage_wildflowers.vox` and
`hearthvale_foliage_leafy.vox` are MCP-authored review candidates, with matching
OBJ/MTL/receipts/baked `.res` files under `assets/models/magicavoxel`.
They use the shared 0.0625 prop grid and greedy export/bake workflow; final triangles are
362 / 380 / 480. Palette indices 2/3/4 retain the restrained greens; wildflowers
also use 5 (pink) and 6 (cream). `foliage-candidates.authoring.json` preserves the
MCP modelling and snapshot history. Raw output stays in ignored staging.
`tests/foliage_asset_test.gd` validates these sources and meshes, and the converter
test covers all six tree/foliage sources. The review scene is
`scenes/foliage_wind_preview.tscn`; `-- --context` shows foliage beneath the trees.
See `reports/Foliage-candidates.md` for captures, motion and validation limitations.

## Meadow expansion review set

Three more plants (`hearthvale_foliage_seedgrass`, `hearthvale_foliage_cream`,
`hearthvale_foliage_mauve`) and three rocks (`hearthvale_rock_slab`,
`hearthvale_rock_split`, `hearthvale_rock_moss`) follow the same staged MCP pipeline.
Their triangle counts are 290 / 330 / 322 and 352 / 468 / 410, respectively.
The plant greens retain palette 2/3/4. Warm cream uses 6/7; muted mauve uses 8/9.
Rocks use warm stone groups 6/10/11, with 2/3 moss on the cluster.
`meadow-expansion.authoring.json` preserves model/edit/snapshot provenance.
Use `tests/meadow_expansion_asset_test.gd` and the shared wind test with
`-- --expansion`. The labelled scene is `scenes/meadow_expansion_preview.tscn`;
`-- --context` shows tree scale. See `reports/Meadow-expansion-candidates.md`.

## Woodland and riverside review set

`hearthvale_foliage_reeds`, `hearthvale_foliage_fern`, and
`hearthvale_foliage_mushrooms` add two gently swaying plants and a static mushroom
cluster: 342 / 450 / 332 triangles. All use the shared 0.0625 prop grid and pipeline.
Reeds retain green groups 2/3/4 plus brown 12; fern uses 2/3/4; mushrooms use cream
6 and warm cap groups 12/13/14. `woodland-candidates.authoring.json` preserves the
MCP source and refinement history. The scene is `scenes/woodland_preview.tscn`;
tests are `tests/woodland_asset_test.gd` and the shared wind test with `-- --woodland`.
See `reports/Woodland-candidates.md` for captures and evidence.

## Compact trees and flat mushrooms

`hearthvale_tree_orchard_compact`, `hearthvale_tree_riverside_young`, and
`hearthvale_tree_wind_low` preserve the approved silhouettes at roughly 80% size.
They contain 4,032 / 2,868 / 3,582 triangles and retain palette groups 1–4.
`hearthvale_foliage_mushrooms_flat` and `_flat_scatter` are low static patches
with 392 / 488 triangles and palette groups 6/12/13/14. Their 0.5-unit height is
lower than the first mushroom cluster. `size-variations.authoring.json` records
the MCP operations and rejected odd-volume scale blockouts. Final tree sources
use corrected even horizontal declared volumes so every face stays on the 0.0625
grid without stretched or collapsed cells. The approved originals are retained
and byte-pinned by `tests/size_variation_asset_test.gd`. Preview all five in
`scenes/size_variations_preview.tscn`; see
`reports/Size-variation-candidates.md` for evidence.

## Fine prop-grid revision

All six gameplay trees, all eleven foliage variants, and the three authored rocks
now use cubic 0.0625 presentation cells while preserving their prior world-space
bounds. Each approved source was doubled through MCP, filled into solid 2x2x2
subcells, and given restrained trihedral half-cell cuts so the silhouette gains
real detail rather than merely changing metadata. Eighteen cut extrema were restored
to preserve every pre-existing asset AABB exactly, and the three compact-tree sources
were rebuilt with corrected even horizontal declared volumes. Mushroom caps are explicitly
validated above their cream stems. `fine-prop-grid.authoring.json` records the
MCP operation pattern, per-asset cut counts, snapshot names, and connectivity review.

## Half-size ground-foliage revision

All eleven gameplay foliage variants are now half the linear size of the 7131d22
revision while retaining cubic 0.0625 cells and their existing brush indices and
placement anchors. Trees and rocks are unchanged. The three mushroom sources keep
broad cap geometry above narrow stems; every independent cluster remains grounded.
The later player-approved palette restoration returns the exact 7131d22
pale-stem/warm-cap colors. Runtime foliage and rock tint variation is deterministic
presentation and does not alter canonical source colors. See
`foliage-halfsize.authoring.json` for the MCP operation record.

## Barrel planter family

`hearthvale_planter_flowers`, `hearthvale_planter_herbs`, and
`hearthvale_planter_light` are actual MCP-authored runtime assets. Their common
editable empty barrel is `hearthvale_planter_barrel.vox`. They retain the
0.75 x 0.75 furniture footprint and cubic 0.0625 decorative cells. The original
`barrel_planter` saved style resolves to the full flower arrangement; herb and
light styles are additive choices. There is no save-schema migration.

`planters.authoring.json` records the palette, source/staging hashes, operation
types and connectivity. Promotion restores only the common 12 x 14 x 12 SIZE
metadata that the MCP writer shrinks during edits; voxel coordinates and
palette entries are verified unchanged. The pivot remains (6, 0, 6) voxels.

Re-export canonical sources with `python tools/magicavoxel/planter_assets.py`,
import with the pinned editor, then use the existing bake script with explicit
`0.0625`. Only explicit `--promote` reads the named MCP staging files. CI uses
canonical sources and never requires the development server or private staging.
The three greedy meshes contain 818 / 696 / 572 triangles respectively.

`tests/m2_planter_asset_test.gd` validates sources, reproducible exports, grid,
materials, preview parity and legacy records. `m2_planter_placement_test.gd`
uses the current controller catalogue and checks cancel, confirm, undo/redo,
recolour, relocation, save/reload and invalid targets. The `planters` cottage
CI shard also runs actual Mobile rendering. Real source contact sheets and

## Gathering table and benches

`hearthvale_table_gathering.vox` is an MCP-authored runtime street-furniture
asset for the `village_table` composition style: a square timber table with a
backless bench on each side. It uses the shared 0.0625 prop grid with a declared
22 x 9 x 32 volume, pivot (11, 0, 16), ground base at Y=0, and the three
restrained timber palette groups #c9a878 / #7d5b43 / #594337. The greedy mesh
contains 280 triangles over 1,178 voxels.

Re-export with `vox_to_obj.py --greedy`, import with the pinned editor, then
bake with explicit `0.0625`. `tests/m2_table_asset_test.gd` validates provenance,
reproducible export, grid, materials, preview parity and legacy records; the
converter test covers its exposed-cell coverage.
