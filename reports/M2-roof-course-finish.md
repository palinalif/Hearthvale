# Roof finish 01 — courses and eave definition

Player approved the roof/material pass following the lighting comparisons. This candidate starts from verified master 461a5da4, not the unresolved catalogue branch. Lighting and the meadow palette are deliberately unchanged to isolate roof appearance. No new art has been merged at source preparation.

## Implemented slice
A final generated-presentation layer adds staggered, tile-sized courses without changing roof authority, saved dimensions, anchors, placement footprints or UI. Native gables retain their original envelope and a continuous lower skin, with one-detail-cell recessed end seams and a seated eave lip. The three existing roof colour batches are retained. Details remain cubic 0.0625-world-unit cells.

Custom hip/shed/saltbox/gambrel slabs are partitioned into disjoint grid pieces with quieter per-tile tint and staggered seam colour: their solid union and silhouette remain unchanged. One instanced batch replaces each existing slab; there is no node, material or draw call per tile. Fill and ridge geometry are untouched. This stage gives custom slabs visual joints, not recessed grooves.

Joined/upper-floor roofs retain their exact established geometry and pitch, but regroup colours using the same coordinate-based course rhythm. Their edge geometry remains unchanged. A subsequent geometry pass is still needed for fully matching lap relief on those roofs; this candidate does not pretend that recolouring solves the joined-roof silhouette problem.

The treatment applies to terracotta, moss tile, slate and wood shake. Thatch, standing seam and green roof keep their existing rendering rather than gaining inappropriate tile joints. Roof colour selection, private materials, highlights, picking cache invalidation and placement ghosts retain their existing routes. Generated-node tags avoid rebuilding the finish on unchanged presentation calls.

## Evidence contract
New layout tests inspect integer spans, half-bond seams, stable negative cell coordinates, solid backing, unchanged gable extents, custom partition volume and cubic detail-grid bounds. Actual Mobile review must capture matched before/after normal/close gables, hip, saltbox, resized steep gable and a genuinely added upper floor (12 images), verify saved-record immutability and visual refresh stability, and report roof instance/batch counts. These are stored under .tools/cottage-repair/roof-courses; the full existing delivery gate is retained. The original builder path is a controlled comparison switch only, never a saved setting. Baseline/candidate use identical lighting, cameras and frozen wind.

At preparation: local source/diff review only. No local Godot executable is installed; a git network probe failed DNS. Pinned CI must establish runtime, images and package verification. No new APK, Drive upload, physical Thor performance improvement or user aesthetic approval is claimed. The exposed lead is GPT-6 Astra Pro, not the repository's preferred Sol; no model switch or subagents are used. Leave the PR draft pending evidence and review.

API reference consulted: official Godot MultiMesh class documentation, including use_colors before instance_count and vertex_color_use_as_albedo. No third-party art or Town to City assets are included. Original user screenshots guide style.
https://docs.godotengine.org/en/stable/classes/class_multimesh.html

Facade/window/foundation depth, contact shading beyond the eave lip, tree crowns and ground/path transitions remain subsequent slices, not completed by this one.
