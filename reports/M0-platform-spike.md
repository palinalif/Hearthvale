# M0 evidence report

Date: 6 September 2026. Status: implementation in progress; M0 is not complete. M1 is not started.

## Environment and delegation

Windows 11 Pro x64 10.0.26200; NVIDIA RTX 3070, driver 591.86. Existing Godot 4.2.2 Mono and templates were preserved. JDK: Eclipse Temurin 17.0.19+10. Existing SDK platforms 34/35/36, build-tools 34.0.0/35.0.0/36.0.0; exports selected 36.0.0. No authorised ADB device was listed. Thor firmware, handheld and external controller mappings, TV/dock, and Android GPU results: **not run**.

Codex CLI 0.153.1. No existing custom agent was found. Project `.codex/agents/luna_worker.toml` pins `gpt-5.6-luna`, `high`, inheriting permissions. The initial test/first workers used `medium`; remaining correctness workers use `high`. A read-only subagent test successfully read project instructions and confirmed the absence of an existing game. Explicit runtime spawn model and effort were requested; independent actual-model metadata was not exposed. No model cache or existing Codex setting/permission was changed. The dock-generated Godot AI MCP server entry was added; a semantic comparison verified all prior settings were preserved. Two coding workers own separate backend/test and controller/scene/test files; the lead owns integration and configuration.

## Dependency proof

Exact archive URLs, hashes and commits: `dependencies.lock.json`. Selected bundle: official Godot `4.7.2.stable.official.ed1daf0bf`, official `4.7.2.stable` export templates, Voxel Tools GDExtension `v1.7x`. Both Godot archives match the published SHA512 sums.

| Check | Actual result |
| --- | --- |
| Desktop editor native classes/data | Passed: VoxelBuffer, VoxelTerrain, VoxelMesherBlocky loaded; two vertical samples read back 11 and 22. |
| Windows release native classes/data | Passed in an exported release executable, exit 0. |
| Android ARM64 debug export | Passed; signed APK verified; ARM64 debug voxel `.so` present. |
| Android ARM64 release export | Passed; signed APK verified; ARM64 release voxel `.so` present. |
| Android debug/release native execution | **Not run**: no Thor connected. Packaging is not loading evidence. |

The early probes were exported before the gameplay systems. Release-mode M0 APKs use the local development signing identity for sideload tests; they are not store-signed production releases. Keys stay outside the repository. The application ID is `org.hearthvale.game`.

Resolved initial failures: wrong VoxelBuffer call signatures in the first probe (fixed by Luna, independently rerun); Android ETC2/ASTC import flag absent (enabled); initial release keystore path was incorrect (corrected through environment variables). Initial export emitted missing-icon error but succeeded with fallback; the game scene adds its own icon before final export.

## Acceptance ledger

| Ticket requirement | Desktop | Physical Thor |
| --- | --- | --- |
| Native dependency loading | Passed probe debug/editor and release | Not run |
| Native app launch | Probe passed | Not run |
| Controller complete route | Pending integration | Not run |
| Visible tunnel/intact roof | Pending integration | Not run |
| Edit, cancel, undo/redo | Pending integration | Not run |
| Save, process restart, corrupt/interrupted recovery | Pending integration | Not run |
| Mobile vs Compatibility fixture/performance | Pending integration | Not run |
| Disconnect and suspension safety | Pending integration | Not run |
| MCP tagged smoke | Partial/failed: core operations passed; existing-script overwrite was reverted on scene save (see docs/mcp-smoke.md) | Development only |
| TV/external controller/audio path | Not applicable | Not run |

MCP runs Godot 4.7.2 + Godot AI plugin/server 3.2.5 in `dev/mcp`; actual session metadata verified both versions. MCP initialization's `serverInfo.version` is the FastMCP framework version 3.4.7, not the Godot AI package version. HTTP and editor WebSocket listeners were verified bound only to 127.0.0.1. No bridge addon exists in the Android game resource tree.

Raw checks are retained locally in `reports/logs`; reproducible commands and final artifacts are documented at handoff. Desktop results cannot establish Thor performance or controller feel.

