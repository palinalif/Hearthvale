# M2 stepping-stone grass contact

## Scope and baseline

Reviewed baseline: `452b0242f78555a0bf75318ecb6de24bad39626a` on
`feat/m2-path-ground-polish`. Baseline Actions run `34658953231` succeeded;
actual-Mobile paths artifact `10285908809` contains all three matched views.

This pass adds only render-derived grass contact. The 452b0242 stone sizes,
distribution, rotations, colours, primary/companion/third-stone positions,
cadence, clipped-octagonal footprints, height sampling, epsilon, thickness,
face winding, normals and materials are preserved. Packed earth and cobblestone,
terrain/save/edit authority and the separate section-placement performance
repair are unchanged. No worker or delegation was used. The exposed task model
is GPT-6 Astra Pro, not the repository's default Sol/high art lead.

## Rendering and bounds

The renderer records primary identity after generating the unchanged stone.
The small contact helper reads the actual generated octagonal footprints;
it does not recompute or modify stone placement. It reuses the existing box
batcher and VegetationMesh's 0.0625 cubic detail tier and restrained greens.

At most 35% of a path's primary stones are selected, never adjacent targets,
with a further 16-per-path and 128-global cap. Small primaries, companions and
third stones are left bare. Each accepted primary gets one uneven two-blade tuft
beside one perimeter segment, not a ring. There are 3-4 cubic cells per tuft;
height is at most 0.1875. Cell footprints conservatively clear every stone top.
Each root and its footprint sample their own native terrain surface. Unsafe
contacts are omitted rather than moved onto the stone or used to mask terraces.

One optional opaque MeshInstance3D surface and one shared vertex-colour material
serve all contacts. Shadow casting is disabled. Maximum added geometry is 512
cells / 12,288 vertices / 6,144 triangles, with no per-frame generation. Actual
fixture counts are emitted as STEPPING_GRASS_AUDIT by the native/Mobile gate.
The legacy stats.draw_calls remains the <=3 path-style batch count;
opaque_surface_draws reports actual material surfaces (<=6 original + <=1 grass).
These are surface budgets, not measured physical-Thor GPU draw/frame timings.

Selection uses stable path ID and cluster identity, sorted independently of path
array order. All geometry is disposable and rebuilt by the existing path refresh;
cleanup removes the previous grass batch immediately. There are no saved offsets,
planting records, new materials per tuft, wind processing or terrain mutations.

## Verification and evidence contract

The existing m2_path_render_test.gd remains in the normal native/Mobile gate,
with every previous assertion and camera retained. Additional checks cover:

- SHA256 locks for the baseline constants and 16 geometry/material functions,
  excluding only the new primary-metadata call from the path function;
- byte-identical stone arrays across grass generation;
- deterministic rebuild, reload and reordered input, plus saturated budget selection;
- native root-height agreement, stone-top clearance, cubic cells, winding and bounds;
- dig/live/cancel/release/undo, preview cancellation and complete removal/rebuild cleanup;
- unchanged complete saved landscape data and explicit surface/geometry accounting.

The real runtime path batch on native terrain is captured with actual Mobile at
1280x720. all-styles.png, stepping-close.png and stepping-reverse.png retain the
baseline cameras, terrain, materials and stone geometry. Compare normal-distance
readability as well as both close views. No raised fixture, substitute ground or
special review material is introduced.

Local source copies were checked against Git blob hashes before editing. Local
Godot/native execution is unavailable in this environment; hosted results must
be read from the exact pushed head. Do not infer passing tests or delivery from
this implementation note. The existing full regression, Mobile, ARM64/Windows
verification and private Drive gates are unchanged. Final run IDs, artifact IDs,
package filenames and receipts belong in the delivery response. Hosted Mobile
is not physical Thor testing; final visual approval belongs to the player.
