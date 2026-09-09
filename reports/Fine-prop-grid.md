# Fine non-terrain prop grid

Player direction: preserve current object dimensions, but use the smaller visual
cell tier for trees, foliage, mushrooms, flowers, and rocks so they read as detailed
miniatures against the terrain.

Follow-up direction supersedes that size constraint for ground foliage: all eleven
foliage variants are now half these dimensions. Trees and rocks remain unchanged.
The cream mushroom surfaces are caps, not stems; broad cream cap geometry is now
above narrow brown stems.

The 20 approved MCP sources were doubled in coordinate space and filled into solid
2x2x2 subcells, preserving their established world bounds when converted at 0.0625.
A restrained trihedral corner pass removes 2,487 half-cells from exposed silhouette
corners without touching downward-facing ground corners. Eighteen extrema were
restored after the generic pass so every pre-existing asset keeps its exact prior
world-space bounds. Every resulting connected
component reaches Y=0; trees and rocks each remain a single component. Mushroom cap
palette surfaces are checked above their cream stem surface.

Gameplay continues to use translation-only MultiMesh instances. Trees and foliage
retain their existing brush variant indices and saves. Rocks now load the authored
slab, split, and moss meshes for the existing three rock indices. Terrain, placement,
collision, cottage structure, and save coordinates remain on 0.125.

Actual desktop Mobile capture: `reports/screenshots/fine-prop-grid.png`. This is a
rendering and regression gate, not physical Thor performance or player approval.
