# M1 physical-feedback iteration 2

Review candidate, 2026-09-06. This continues the functioning editable cottage and continuous sculpting milestone. No M2 work. Visual approval and physical Thor results remain separate from automated evidence.

## Changes

- Native terrain and derived cottage, tree, foliage and rock steps share a **0.125 world-unit cell edge**. The earlier intermediate captures with .5 terrain beside finer assets were rejected and are retained as evidence, not the handoff result. Larger surfaces merge integer cell spans; decorative cells are not simulated blocks.
- Native dimensions are 384×256×384 in the unchanged 48×32×48 world. Legacy terrain is expanded exactly, preserving caves/materials/edits and original checkpoint files. Existing coarse landforms keep their shape; subsequent edits and freshly generated contours use fine cells. Each raw terrain generation is **72 MiB**.
- Fresh cottage scale is .25, half the previous build's linear scale. Existing saves retain their transforms until **Cottage → Miniature scale**, an undoable conversion. Roof courses and trim regenerate on the shared grid after transforms. Trees have rebuilt fixed-cell crowns approximately 4.8–6 units tall.
- Automatic windows add/remove/reflow with available wall space, reserve protected/suppressed footprints and hide optional shutters when crowded. Manual flower boxes and shutters remain editable. Unsupported modified/manual details remain recoverable.
- Default sculpt strength is 6 instead of 1.5, with quarter-rate precision and controller range .5–16. Flatten retains its target and per-column advancing surface, handles both raising and lowering, and stops at cave voids. Cursor feedback follows the advancing brush front.
- Terrain menu adds **Foliage brush**, **Tree brush** and **Clear planting**. Default trees/foliage/rocks are saved placements. Terrain clears roots near actual changed cells. A stroke and its planting removal share undo/redo; cancellation, save/reload and cold restart retain both layers. Interactive planting samples the aimed-at exposed surface, including cave floors, after snapping its root position.

Main Astra implemented production visuals and scene integration. Two explicitly configured gpt-6-astra/high workers handled bounded backend and building/checkpoint fixes and tests; each first passed read-only delegation. The runtime did not independently expose resolved model metadata. Luna was not used for this production pass. Dependencies and permissions were preserved.

## Pinned environment

Godot **4.7.2.stable.official.ed1daf0bf**, matching 4.7.2 export templates; Voxel Tools GDExtension **v1.7x**, commit **75d3c6d996ed2331c80edcd8c3ebc947afc0f041**. Mobile/Vulkan renderer. Native mesh chunks now32 (the pinned API supports16/32), data chunks remain16. Windows11, Ryzen2700X, RTX3070, NVIDIA591.86. Temurin JDK17.0.19+10, Android SDK build-tools36.0.0. No engine or native terrain backend replacement.

## Desktop measurements

Actual 1280×720 Mobile scene, VSync disabled,60fps cap, isolated temporary save. Short samples:60 idle frames,60 held moving sculpt frames,30 forced resize-preview rebuilds. These are development measurements, not sustained Thor performance.

| Phase | Median | 95th percentile | Notes |
|---|---:|---:|---|
| Idle |16.65ms|16.72ms|715 draw calls|
| Sustained Raise |16.73ms|19.43ms|5,120 changed cells; commit confirmed; backend CPU5.39ms p95|
| Repeated resize rebuild |31.44ms|37.29ms|Presentation CPU29.89ms p95; remains a cost to improve|

[Machine-readable final profile](m1-iteration2-desktop-profile.json). Godot static memory reached about488MB during sculpting; native/GPU memory is not fully represented by that monitor. Fine-grid test measured native readiness1.505s, legacy load+upsample375ms, fine checkpoint publication1.696s on this host.

An early actual sculpt profile was225ms median/290ms p95. Fixes removed repeated whole-stroke scans/string allocation, batched native updates and repeated vegetation draws, bounded surface-plane probes to49 and used a small exact-cell centre highlight alongside the full brush ghost. The final path preserves elapsed brush time, strength, native resolution and authoritative edits. A local fitted plane estimates neighbourhood slope; it does not inspect every fine surface feature.

## Verification and render review

The full runner completed import/native loading, M0 checkpoint38 plus four restart fixtures, M1 checkpoint47 plus four restart fixtures, native backend83, sculpt188, scaled backend29, visual openings6, building data tests, fine resolution/migration46 plus cold11, landscape controller/history32 plus cold6, headless geometry660 and M0 controller checks. The runner then correctly stopped at outdated/failed M1 controller expectations. After corrections, M1 controller passed, targeted planting9 passed, and the full M1 acceptance write scenario112 plus cold read8 passed. Logs are under `reports/logs/iteration2-*`; no failed attempt is counted as passing.

Final actual **Mobile** geometry validation passed87,608 checks, inspecting762,776 vertices and28,982 MultiMesh transforms across cottage scales/resizes and translated planting batches; zero headless-unverified instances in that run. Final exported Windows runtime smoke ran180 frames using isolated review settings, reported Forward Mobile/RTX3070 and exited0 without error diagnostics. This proves desktop startup, not physical Android gameplay.

Failures corrected during integration included inferred GDScript types, complete-envelope versus cottage-only comparisons, historical terrain dimension expectations, and loss of the eight-world-unit airborne cursor search reach when native cells became smaller. The controller fixture now checks intact terrain after a long Dig can legitimately exhaust a column. The cold test additionally verifies the loaded cottage is applied to the playable world. The landscape suite separately verifies the saved planting envelope and cold recovery.

Actual Mobile captures: [normal](screenshots/m1-iteration2-final.png), [close](screenshots/m1-iteration2-close-final.png), [resized with moved detail](screenshots/m1-iteration2-edited-final.png). Debug overlay is hidden. [Previous accepted-for-further-playtest scene](screenshots/m1-astra-final.png), [rejected coarse/fine intermediate](screenshots/m1-iteration2-first.png), and [oversized ground planting before final revision](screenshots/m1-iteration2-oversized-planting.png) remain available for comparison. The normal view retains the earlier camera distance; close uses16 instead of26 to inspect the smaller cottage.

Reference imagery was inspected directly, including `docs/references/rulebook/images/station-to-station-00.jpg` and the Town to City board. The final terrain contours now have the same step size as the assets; trees rise above the cottage. Inspection prompted smaller ground-plant and rock cell counts without shrinking their cells. Remaining visual gaps include plain broad terrain/material transitions, regular roof courses and simplified tree crowns compared with the references. Palette and scene composition need the requested subsequent review; these captures do not constitute player approval.

## Playable artifacts

Android Mobile ARM64 debug: `builds/hearthvale-m1-iteration2-debug.apk`, **version5 / 0.1.2-m1-garden**,37,612,945bytes. SHA256 `0138d46cf80982154a25da499c9796dcdae9157718095482091cdd46b8c5393e`. Windows Mobile debug: `builds/hearthvale-m1-iteration2-debug.exe` with adjacent exported resources. Both exports exited0; complete import/export logs contain no script/error diagnostics.

[APK verification](m1-iteration2-apk-verification.json) passed signature, previous signing-certificate match, package/version, Mobile manifest, ARM64-only and exact pinned native-library content. Development tools/MCP/reference resources are excluded. AAPT reports a template themed-icon resource warning; it did not fail export or signature verification. Physical Android launch remains untested. The preceding `hearthvale-m1-debug.apk` remains unchanged (SHA256 `fd1c2f342355c22f9e39641b1f73ac6be4b85586ab0ad623302d2fe8bf2e9423`). Early export verification is historical and superseded by the final file/hash above.

## Open evidence

Physical Thor install, controller feel, sustained frame time, memory/thermals and save interruption checks: **not run for this build**. Earlier player feedback is retained but does not validate this new resolution. The native API still provides no per-edit mesh-completion acknowledgement. Palette review remains requested; colours are a candidate, not approved. The small scene is not a claim of matching all reference-game art quality.

Godot AI MCP remains pinned3.2.5 and isolated from exports. Its prior open-script overwrite persistence check is **partial/failed**, not repaired or newly passed here; see [MCP evidence](../docs/mcp-smoke.md). Command-line checks remain independent.

Google Drive upload is authorized, but this session exposes no Drive upload connector or mounted Drive destination. No upload or public sharing is claimed.

## Reproduce and playtest

See [build/test commands](../docs/build-and-test.md). Run `./tools/check.ps1 -TimeoutMs 240000`, then actual-rendered `tests/visual_grid_test.gd -- --require-rendering`. Capture via `tools/capture-m1.ps1` with isolated review flags. Preserve old APKs and player checkpoints.

Thor checklist: update-install without uninstalling; check terrain/plant cell size together; use Miniature scale on an existing cottage; hold Raise/Dig and Level across a slope; paint trees/foliage, sculpt their roots, undo/redo and reload; resize through window-count changes with moved/suppressed/manual details; report responsiveness, scale, placement clarity and frame/memory overlay readings. Use the full existing M1 cottage regression before milestone acceptance.
