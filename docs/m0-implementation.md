# M0 implementation boundaries

The scene uses the native Voxel Tools GDExtension. The patch is 48 × 32 × 48 cells; its blocky material library contains air, stone, and grass. `PatchGenerator` creates deterministic terrain, a tunnel with intact terrain above it, and a separate basin for the water-material experiment. These are M0 fixtures, not a biome or water simulation.

`TerrainBackend` owns the authoritative native `VoxelBuffer`. A committed sphere is one synchronous command. The native buffer tool performs the sphere operation; only the clipped changed region is transferred to `VoxelTerrain`. Undo and redo store before/after voxel regions, bounded to 50 commands and 128 MiB. Previews live in the presentation layer and do not mutate terrain. A no-op does not consume history or increment the revision.

Meshes are derived by the pinned native extension. The API exposes initial mesh readiness, but does not provide a reliable mesh-completion acknowledgement for each subsequent edit revision. The overlay deliberately reports that acknowledgement as unavailable. Application-owned terrain writes are synchronous and ordered; there is no custom asynchronous mesh job scheduler or voxel engine in M0.

`CheckpointStore` writes complete terrain values rather than replaying editing commands. A generation consists of a bounded binary payload and a JSON manifest containing schema, dimensions, generator ID, revision, generation number, and SHA256. Data is staged, flushed, checked and published before the manifest is published. Loading validates candidates from newest to oldest; retention keeps two valid generations. This does not claim protection from arbitrary storage hardware failure or establish Android filesystem behavior without device testing.

Schema 2 uses the pinned native backend's raw 16-bit channel bytes and records layout, channel, and depth. Schema 1's earlier explicit coordinate-loop payload remains readable; subsequent saves use schema 2. The payload is still a complete bounded generation, with the same publication and recovery contract.

`m0_scene.gd` owns action mapping, camera, world cursor, preview, pause menu, sun/water presentation, debug display, and the repeatable fixture. Test and benchmark checkpoint roots are separate from player saves. There are no villagers, building catalogues, building generators, or later-milestone systems.

The MCP sandbox is a separate Godot project under `dev/mcp`, excluded from game imports and exports. Its observed bridge limitation and actual operation evidence are recorded in `mcp-smoke.md`.
