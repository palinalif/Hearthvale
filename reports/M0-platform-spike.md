# M0 evidence report

Date: 6 September 2026. Status: M0 handoff with subsequent player-reported Thor playtest success. **M0 is not complete**: detailed acceptance evidence remains outstanding and the MCP smoke has a documented persistence failure. M1 was not started at this handoff; the player subsequently authorized its implementation with these evidence gaps still open.

## Subsequent player feedback

On 6 September 2026, the player reported manual testing on the Thor and said it was working fine. Record this as **user-reported physical playtest success**. The APK variant, firmware, exact checks performed, and performance measurements were not supplied; the original per-check ledger below records the lead's handoff evidence and is not retroactively marked passed by this general report.

The player also found terrain resolution much too coarse. `docs/design.md` and `docs/references/README.md` now establish Town to City and Station to Station as primary visual references, retain Tiny Glade for building interaction and the original images for terrain/geography, and require substantially finer visual detail independent of the terrain editing grid. The M1 ticket records a cottage-and-riverbank visual review before catalogue expansion. This documentation update changes no M0 runtime, APK, scope, or test result.

Subsequent feedback about uncertain terrain placement, clunky controls, the thick cyan ring, and a desired ghost volume is tracked separately in `M0-placement-followup.md`. The measurements and artifact hashes below describe the original `0.0.1-m0` handoff; follow-up results must not be inferred from them.

## Environment and delegation

Windows 11 Pro x64 10.0.26200; AMD Ryzen 7 2700X (8 cores/16 threads), 31.9 GiB RAM; NVIDIA RTX 3070, driver 591.86. A Parsec virtual display adapter is also installed. Existing Godot 4.2.2 Mono and templates were preserved. JDK: Eclipse Temurin 17.0.19+10. Existing SDK platforms 34/35/36, build-tools 34.0.0/35.0.0/36.0.0; exports selected 36.0.0. ADB 1.0.41 / platform-tools 37.0.0-14910828 listed no authorised device. Thor firmware, handheld and external controller mappings, TV/dock, and Android GPU results: **not run**.

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
| Native app launch | Exported Windows debug/release Mobile and Compatibility release passed | Not run |
| Controller complete route | Action/event regression passed; physical pad feel/mapping not tested | Not run |
| Visible tunnel/intact roof | Passed: native opening/roof samples and rendered capture | Not run |
| Edit, cancel, undo/redo | Passed: native equality, bounds, no-op, preview and menu gates | Not run |
| Save, process restart, corrupt/interrupted recovery | Passed file-process fixtures, fresh native backend loading, schema migration and recovery tests | Not run |
| Mobile vs Compatibility fixture/performance | Both 60-second rendered runs passed; stalls measured below | Not run |
| Disconnect and suspension safety | Injected disconnect/focus-out and fixture interruption tests passed | Not run |
| MCP tagged smoke | Partial/failed: core operations passed; existing-script overwrite was reverted on scene save (see docs/mcp-smoke.md) | Development only |
| TV/external controller/audio path | Not applicable | Not run |

MCP runs Godot 4.7.2 + Godot AI plugin/server 3.2.5 in `dev/mcp`; actual session metadata verified both versions. MCP initialization's `serverInfo.version` is the FastMCP framework version 3.4.7, not the Godot AI package version. HTTP and editor WebSocket listeners were verified bound only to 127.0.0.1. No bridge addon exists in the Android game resource tree.

Raw checks are retained locally in `reports/logs`; reproducible commands and final artifacts are documented at handoff. Desktop results cannot establish Thor performance or controller feel.

## Implemented scope and review

The source is described in `docs/m0-implementation.md`. The 48 × 32 × 48 patch is native volumetric voxel data with a through-tunnel, an intact roof, and a separate water basin. The scene includes a bounded orbit camera, movable 3D cursor, visible sphere preview, explicit add/remove transactions, cancel, undo/redo, controller-focused save/reload/quit, sunlight, water shader, and a debug overlay. No later-milestone gameplay was added.

Checkpoint schema 2 uses native 16-bit channel bytes. Schema 1 remains readable, with full-value migration comparisons. Tests cover corrupt newest generations, missing data, unpublished staged files, malformed metadata, invalid write roots, bounded sizes, generation ordering, and retention of two valid generations. Separate process fixture writes and reads compare data hashes; fresh native backend instances verify loaded terrain values and revision. These are desktop process/data checks, not Android power-loss tests.

Lead review rejected and corrected initial native API misuse, paste-to-buffer rather than paste-to-terrain, no-op/history defects, ambiguous generation ordering, inadequate corruption fixtures, duplicate controller-test dispatch, overlapping HUD text, a buried water surface, and incomplete archive extraction paths. Temporary captures that read an in-progress worker edit produced parse errors and were stopped; subsequent stable checks must pass before handoff.

The first short renderer probe showed about 80 ms frame pacing with VSync enabled on this desktop. An explicit `--disable-vsync --max-fps 60` comparison brought short-run typical frames to about 16.7 ms. Initial coordinate-loop checkpoint writing caused approximately 69 ms combined edit/undo/redo/save cycles. Native channel-byte writing reduced a separately measured save to 24.556 ms in the lead's schema 2 check (legacy migration save: 35.245 ms). These short diagnostics motivated the final repeatable runs; they do not establish sustained device performance.

Lead independently ran the final native/checkpoint core tests: **38 checkpoint checks and 33 backend checks passed**. The malformed-depth test intentionally triggers Voxel Tools' warning that changing a populated channel's depth resets it; production saves reject that depth. Native startup, shader, and script errors are failures, even when Godot returns exit code zero. The build/check scripts enforce this log check.

The controller regression injects joypad button events and action-state axes in a real scene tree. It checks move/orbit/zoom, brush/height, add/remove, cancel without native mutation, undo/redo, D-pad menu focus, menu gating, save/reload, injected focus-out/disconnect, and the private fixture's completion/restoration. A final interruption case presses B/A/D-pad during an active fixture: input stays blocked until the benchmark finishes, preventing the benchmark coroutine from switching to and modifying a player backend. These are automated desktop input tests, not claims about the Thor's built-in mapping. The preview material renders its entire translucent sphere through terrain so interior edits remain visible.

## Desktop renderer measurements

Both runs used the same generated native patch and elapsed-time camera route, 1280 × 720, NVIDIA RTX 3070, `--disable-vsync --max-fps 60`, after imports and short shader/renderer diagnostics. Native initialization is outside the timed interval. A cycle at the beginning and approximately every two seconds alternates a real terrain edit, then undo, redo, and a checkpoint save. The scene ran for approximately 60 seconds per renderer; this is not a thermal or populated-village benchmark.

| Observed metric | Mobile (Vulkan 1.4.325) | Compatibility (OpenGL 3.3) |
| --- | ---: | ---: |
| Elapsed seconds / frame samples | 60.006 / 3,584 | 60.008 / 3,581 |
| Frame p50 / p95 / p99, ms | 16.666 / 16.694 / 17.013 | 16.666 / 16.715 / 17.074 |
| Slowest frame, ms | 47.224 | 57.467 |
| Edit + undo + redo + save cycle p95, ms | 42.938 | 49.928 |
| Successful edits / undos / redos / saves | 30 / 30 / 30 / 30 | 30 / 30 / 30 / 30 |
| Final frame draw calls / drawn primitives | 25 / 64,376 | 69 / 64,396 |
| Godot static-memory counter, MiB | 60.2 | 48.3 |
| Script/native errors | None in run log | None in run log |

The per-frame primitive counter includes rendered passes/UI; it is not a unique terrain-triangle inventory. Static memory is Godot's instrumented allocation counter, not total process or GPU memory. Exact GPU memory was **not measured**. Exported release templates return zero for unavailable static-memory instrumentation; the final overlay labels it **unavailable**, and JSON uses `null` plus an availability flag. The overlay's rolling 240-frame percentiles can differ from the complete-run JSON.

The measured save cycles still exceed a 16.7 ms frame budget, and the default VSync desktop path showed poor pacing. Neither renderer is certified for Thor performance. Raw counters and context are preserved in `reports/performance/desktop-mobile.json` and `desktop-compatibility.json`; full logs are local under `reports/logs/lead-benchmark-*-60s.log`. Later changes only gated fixture transitions, improved preview visibility, and labelled unavailable release telemetry; the timed CLI route/native workload was unchanged.

## Reproduce and inspect

Run `tools/bootstrap.ps1`, `tools/check.ps1`, and `tools/build.ps1 -Windows -Compatibility` from the project root. Exact individual commands, prerequisites and signing behavior are in `docs/build-and-test.md`. Bootstrap was independently exercised against a fresh installation destination using the locked local cache, then rerun against both the staged and existing installations. Required dependency bytes were verified and no existing different file was overwritten.

The lead ran the complete bounded check script, then reran the controller regression after the final fixture guard. The four checkpoint fixture subprocesses wrote/read revisions 77 and 88 with identical respective hashes. No test uses the player's normal checkpoint root. Rendered water, preview and both renderer captures were inspected. `reports/screenshots/m0-preview-mobile.png` shows the volumetric preview and intact tunnel roof; `m0-water-mobile.png` shows the separate water test; `m0-mobile-final.png` and `m0-compatibility-final.png` show the debug overlay. Earlier `*-review.png` / `m0-first-mobile.png` images are diagnostic failures/iterations, not the final presentation.

Final artifact hashes, sizes and signature verification are in `reports/apk-verification.json`. ARM64 library names/sizes and byte comparisons against the pinned package are in `reports/apk-contents.json`. All APKs are ARM64-only and exclude the MCP sandbox, tests and reference documents. Both development-signed modes use the same certificate; no key or device identifier is committed. The Windows Compatibility export selected OpenGL without a command-line renderer override, verifying the custom export feature. Android selection must still be confirmed from the overlay on the device.

Final manifest inspection caught an Android export distinction: custom feature settings selected Compatibility in Windows, but the Android exporter still wrote `mobile` metadata. A temporary runtime `override.cfg` also failed to change that metadata. Luna corrected the build script to guard, back up, temporarily change the two actual project renderer settings, export, and restore the original bytes. The lead reran `tools/build.ps1 -CompatibilityOnly`, verified `org.godotengine.rendering.method=gl_compatibility` in the rebuilt APK, and independently confirmed byte-for-byte project restoration with no leftover backup. The rebuilt Compatibility APK's signature, native library and resource exclusions were verified again.

Manifest/package inspection records minimum SDK 24 and target/compile SDK 36. SDK 36 AAPT2 badging completed successfully, with a warning about an unused themed-icon file reference absent from the archive; the application icon points to a present resource. Legacy AAPT badging rejected the template's string-typed optional Vulkan `required=false` attribute, although its XML-tree inspection succeeded. These observed tooling issues are retained in the local AAPT logs; neither successful export nor AAPT2 parsing proves installation on Android. Physical installation remains **not run**.

After the final telemetry change, the lead rebuilt all artifacts and launched the exported Windows debug, release, and Compatibility release executables independently. Each ran the native fixture for three seconds, completed two edit/undo/redo/save cycles, and exited zero without errors. Release memory correctly reported unavailable; debug instrumentation reported a positive value. Summaries are in `reports/windows-runtime-verification.json`. Final APK signatures and native package contents were verified again. A final ADB check still listed zero devices, so no APK installation or physical launch is claimed.

## Remaining acceptance work

1. Run the debug and release APKs on the physical Thor and establish actual native loading, firmware, controller mappings and app restart behavior.
2. Playtest the full built-in-controller route, suspension/disconnection, camera/cursor feel and on-device save recovery. Use Start → Run 60s fixture and repeat with the Compatibility APK; record display, VSync, fan/performance mode, power and thermal context.
3. Test TV/dock, external pad and audio when available; otherwise retain **not run**.
4. Resolve or explicitly accept the pinned MCP bridge's existing-script overwrite persistence failure. Core editor operations passed; the full smoke is not marked passed.

Use `docs/thor-playtest.md` for the short device checklist. The original M0 gate prohibited M1 before acceptance; the player's subsequent authorization supersedes that implementation restriction, while leaving the required evidence open. Save-cycle stalls, unavailable per-edit native mesh acknowledgements, release memory telemetry limits, and the MCP failure remain explicit limitations.

