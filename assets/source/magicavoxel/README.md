# MagicaVoxel source assets

These `.vox` files are project-authored sources produced through the pinned
`Mahinika/magicavoxel-mcp` development server. The server is not shipped with
the game. Approved sources are converted by `tools/magicavoxel/vox_to_obj.py`;
generated OBJ, MTL, baked RES, and `.asset.json` receipts live under
`assets/models/magicavoxel`.

Authoring convention: one MCP voxel is `0.125` world units and MCP Y maps to
Godot Y. Keep pivots at the horizontal centre of the declared VOX dimensions
and the model base at Y=0. The converter removes hidden faces and preserves one
surface material per used palette index. Candidate assets must pass
`tests/magicavoxel_asset_test.gd` and an actual Mobile render before runtime use.

Godot's OBJ importer applies tiny compression drift, so
`tools/magicavoxel/bake_mesh.gd` snaps the imported mesh back to the declared
grid and saves the runtime `.res`; gameplay loads that baked resource.

The MCP writes only to the ignored `.tools/magicavoxel` staging directory.
Promote a reviewed source explicitly; never point the server at this canonical
directory.
