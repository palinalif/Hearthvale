# Fine non-terrain prop grid

Player direction: preserve current object dimensions, but use the smaller visual
cell tier for trees, foliage, mushrooms, flowers, and rocks so they read as detailed
miniatures against the terrain.

Follow-up direction supersedes that size constraint for ground foliage: all eleven
foliage variants are now half these dimensions. Trees and rocks remain unchanged.
Broad mushroom cap geometry remains above narrow stems, while the source palette
returns to its earlier pale stems and warm brown caps.

The 20 approved MCP sources were doubled in coordinate space and filled into solid
2x2x2 subcells, preserving their established world bounds when converted at 0.0625.
A restrained trihedral corner pass removes 2,487 half-cells from exposed silhouette
corners without touching downward-facing ground corners. Eighteen extrema were
restored after the generic pass so every pre-existing asset keeps its exact prior
world-space bounds. Every resulting connected
component reaches Y=0; trees and rocks each remain a single component. Mushroom cap
palette surfaces are checked above their cream stem surface.

Gameplay uses deterministic cardinal rotations for trees and foliage, preserving
the voxel grid while varying silhouettes in both the starter scatter and brushes.
Foliage and rock MultiMesh instances carry restrained deterministic color modulation
without extra draw batches. Existing brush variant indices and saves are unchanged.
Rocks load the authored slab, split, and moss meshes for the existing three rock
indices. Terrain, placement, collision, cottage structure, and save coordinates
remain on 0.125.

Actual desktop Mobile capture: `reports/screenshots/fine-prop-grid.png`. This is a
rendering and regression gate, not physical Thor performance or player approval.

The placement-variation follow-up is shown in
`reports/screenshots/foliage-halfsize.png`. The focused actual Mobile capture passes
2/2 checks, the full actual Mobile visual grid passes 322,746 checks across 107,099
instances, and the normal regression suite passes. Local checkpoint fixtures for
that suite were redirected under ignored `.tools` storage because the host C: drive
had only about 38 MB free; CI retains its normal isolated user-data path.
