# Dependency and asset origins

- Godot Engine 4.7.2, MIT license: https://github.com/godotengine/godot/tree/4.7.2-stable . Official engine and export-template archives are pinned with SHA512 in `dependencies.lock.json`.
- Zylann Voxel Tools GDExtension v1.7x, commit `75d3c6d996ed2331c80edcd8c3ebc947afc0f041`, MIT license: https://github.com/Zylann/godot_voxel/tree/v1.7x . Preserve the package's `addons/zylann.voxel/LICENSE.md` with installed binaries. The extension's manifest selects its distinct debug/release native libraries. No local native source modification.
- Godot AI plugin/server 3.2.5, MIT license: https://github.com/hi-godot/godot-ai/tree/v3.2.5 . Installed only in the disposable `dev/mcp` project; excluded from game resources and APKs. See its bundled license. Telemetry disabled through `GODOT_AI_DISABLE_TELEMETRY=true` for the development process.
- MagicaVoxel MCP Server, commit `710671d49bdc89e4e3d1ff7c60541c1d0383ac16`, MIT license: https://github.com/Mahinika/magicavoxel-mcp/tree/710671d49bdc89e4e3d1ff7c60541c1d0383ac16 . Installed under the user's private Codex tools directory and confined to ignored Hearthvale staging folders; neither the server nor its Python environment ships in game resources. Project-authored `.vox` sources retain conversion receipts under `assets/models/magicavoxel`.
- The supplied `docs/references` images belong to their credited creators and remain design references only. They are excluded from the game. No scenery was extracted into game assets.
- Project shaders, icon, scene materials, and terrain fixture are generated project code. No downloaded production art, fonts, music, or audio were added.

GUT and Input Helper remain uninstalled: M0 uses Godot's command-line test scripts and built-in action system. These shortlist candidates were not assumed compatible or required.
