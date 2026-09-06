# M1 — editable cottage and continuous sculpting handoff

Date: 6 September 2026. **Ready for physical playtest; M1 is not complete.** Both authorized tickets are implemented for review. Required Thor controller/visual/performance evidence is not run on this build. No M2 or catalogue expansion has started.

## Delivered behavior

- One procedural, controller-selectable cottage with width/depth/height resize handles and precision snapping. Six generated windows can be moved in their supporting wall plane, replaced or suppressed; a manual flower box can be added. Material changes, cancellation, undo/redo, save/restart and independent duplication are implemented.
- Stable detail identities, separate overrides/exclusions/manual records and recoverable needs-placement records preserve choices through shrinking and deleted supports. Derived rendering uses revision checks. Complete design comparisons exclude only monotonic revision/ID-allocation bookkeeping.
- Continuous raise/dig, fixed-height level, fixed-slope level and local geometric smooth. Holding still advances the surface; dragging interpolates a connected stroke. Strength is time-based. Release commits one transaction, B restores the entire stroke, and menus/pause/focus loss/disconnection cancel pending work with a fresh-press requirement.
- Controller tools expose radius, strength, falloff, precision, keep-reference, resample and optional height snapping. Raise/dig support ground, wall and ceiling targeting. Level/slope/smooth use ground references for pads and banks; unsupported wall/underside flatten references are rejected explicitly.
- A faint influence volume and thin local surface highlight replace the thick cyan cursor in M1. This shows sculpting influence, not an instantaneous exact cut. The separate retained M0 stamping scene keeps its exact changed-cell preview.
- The bounded cottage/riverbank uses muted materials, sunlight, water and stepped trees. Town to City and Station to Station are primary visual references; Tiny Glade remains the interaction reference. Screenshots are a review candidate, not approved final art.

Main implementation: scripts/m1_scene.gd, scripts/cottage_visual.gd, scripts/building_world.gd, scripts/terrain_backend.gd, scripts/m1_patch_generator.gd and scenes/m1.tscn; checkpoint and test changes are recorded in the commits. [Controller instructions](../docs/M1-controller-and-review.md).

## Representation and preservation

M1 uses **96 × 64 × 96 native cells at 0.5 world units per cell**, retaining the original **48 × 32 × 48 world-unit extent**. This doubles resolution on each axis (eight times the cells), without increasing world size. Decorative geometry has its own finer detail scale. This remains a candidate pending Thor costs and player approval, not a final terrain-grid decision.

The pinned native voxel backend still owns TYPE16 terrain and blocky meshing, including caves and overhangs. Brush updates are local native writes with sparse first-touch originals; no full-world snapshot per brush update or custom voxel engine was introduced. History is bounded.

M0 retains its original scene, grid, reader and checkpoints. M1 uses a separate user://m1_checkpoints root. Schema 3 publishes the exact bounded cottage document and native terrain together in one verified generation, with fallback generations. Native M1 payload is **1,179,648 bytes**. Terrain/building revisions count independent edits; consistency comes from one synchronous snapshot and generation publication, not equal counters.

The internal Godot application name remains Hearthvale M0 to preserve the existing user-data location. The M1 window/application display and Android version identify M1. Android retains package org.hearthvale.game, now version code **3**, version **0.1.0-m1**. Existing saves and earlier build artifacts were not erased.

## Exact dependencies and delegation

- Godot **4.7.2.stable.official.ed1daf0bf**, matching official **4.7.2** export templates.
- Voxel Tools GDExtension **v1.7x**, commit **75d3c6d996ed2331c80edcd8c3ebc947afc0f041**. Origins/archive hashes: dependencies.lock.json.
- Temurin JDK **17.0.19+10**, Android build-tools **36.0.0**, ADB **37**.
- Development MCP: Godot AI **3.2.5**, separate development sandbox, excluded from runtime.
- Codex **0.153.1**. Existing project Luna configuration explicitly selects **gpt-5.6-luna/high**. The read-only delegation gate passed; independent actual-model metadata was not exposed. No model cache, permission or unrelated configuration changes.
- Coding and test-writing were delegated to Luna with separate owned files and no more than two concurrent coding workers. The lead reviewed changes, ran final integration checks, inspected rendered captures, exported and verified artifacts.
- Desktop: Windows 11, Ryzen 2700X, RTX 3070, 32 GB RAM. Authorized Android devices: **0**; no M1 installation or physical Thor test was performed.

## Final independently run checks

Command: **./tools/check.ps1** — **exit 0, check ok** after the final code changes. Logs are in reports/logs/check-*.log. These are automated checks, not physical controller comfort evidence.

| Check | Final result |
| --- | --- |
| Project import and native dependency probe | Passed |
| Retained M0 checkpoint regression | 38 checks, 0 failures; four independent process modes pass |
| Retained M0 backend and controller | Backend 83/0; controller exit 0, zero failures |
| M1 combined checkpoint and recovery | 23/0; four independent write/read process modes pass |
| Continuous sculpt geometry/history/time comparison | 116/0 |
| World-scaled native M1 backend | 27/0 |
| Building records, attachment footprints, validation/budgets, duplicate independence and renderer | Exit 0, zero failures |
| Targeted M1 controller routing, previews and modal safety | Exit 0, zero failures |
| Full actual joypad-event M1 regression | **88/0**, no missing UI routes |
| Complete controller save fixture in another process | **88/0**, then cold-read **7/0**; exact native-byte and complete canonical design hashes match |

The full controller regression covers the six-window/manual-flower-box workflow, resize/material changes, cancellation, history, orphan recovery/deleted support, duplication, fixed plane keep/resample and input interruptions. Interruption fixtures first verify actual changes, then verify cancellation and no held-action restart, followed by a fresh press that edits successfully. Stale derived revisions are rejected.

Stationary and moving equal-duration 30/60 FPS sculpt fixtures produced **zero differing authoritative bytes**. Smooth/flatten tests check geometric convergence and locality; cave tests distinguish floor/ceiling and prevent digging from jumping across a newly exposed void. This is fixture evidence, not a guarantee for all frame schedules.

## Rendered desktop review

Actual 1280 × 720 Godot Mobile captures, inspected by the lead:

- [Normal cottage and riverbank](screenshots/m1-normal-mobile.png)
- [Close cottage detail](screenshots/m1-close-mobile.png)
- [Terrain influence highlight and ghost](screenshots/m1-terrain-mobile.png)
- [Scrollable controller tools](screenshots/m1-menu-mobile.png)

Capture used the pinned GUI executable with --disable-vsync --write-movie <frame.png> --fixed-fps 30 --quit-after 60, and the scene's --review-close, --review-terrain or --review-menu flags for the corresponding view. Final frame 59 was retained. Logs: reports/logs/m1-final-render-*.log. No script/native errors in the final captures. MovieMaker timing is visual QA, not a performance measurement.

All three exported Windows executables were launched independently with --disable-vsync --max-fps 60 --print-fps --quit-after 600. Each exited 0 without script/native errors. Debug/release selected Vulkan Mobile; Compatibility selected OpenGL without a command-line renderer override. Reported idle samples were 60 FPS / 16.66 mspf in all three runs. This short capped desktop smoke does **not** measure sustained sculpting, Thor frame pacing or thermals. [Full Windows verification](m1-windows-verification.json).

## Exported artifacts

Command: **./tools/build.ps1 -Windows -Compatibility** — **exit 0**, all six exports succeeded. The temporary Android Compatibility configuration restored project.godot byte-for-byte. Build logs: reports/logs/build-*.log.

| Android artifact | Bytes | Renderer |
| --- | ---: | --- |
| [M1 debug APK](../builds/hearthvale-m1-debug.apk) | 37,562,970 | Mobile |
| [M1 release-mode APK](../builds/hearthvale-m1-release.apk) | 34,011,269 | Mobile |
| [M1 Compatibility APK](../builds/hearthvale-m1-compatibility.apk) | 37,562,970 | OpenGL Compatibility |

All APKs passed apksigner verify; signing certificates match the previous M0 debug build. These personal builds use the existing development signing identity, including release mode. Each contains only ARM64 native libraries, the compiled M1 script and the exact pinned voxel library bytes for its export mode. Development tools/tests/docs/reference resources are excluded. Manifest package, version and renderer metadata passed inspection. [Exact SHA-256 values and APK verification](m1-apk-verification.json).

Windows debug, release and Compatibility .exe/.pck outputs and native DLLs are in builds/. Keep each executable with its companion package and native DLLs.

Reproduce using [build/test instructions](../docs/build-and-test.md). Install as an update, preserving app data; do not uninstall M0 to work around an update failure. No device installation command was run.

## Failures, limitations and remaining evidence

Earlier independent controller tests failed native readiness because the custom patch omitted the native empty generator. This was fixed and the final suite passed. Reviews also found attachment/support preservation, document/history budgets, centre-hit sampling, held-action leakage, advancing sculpt surfaces and renderer discrepancies. Luna corrected these; final regression and rendered captures were rerun afterward. Earlier failed/intermediate logs are not counted as final passes.

The retained M0 checkpoint negative fixture intentionally emits a VoxelBuffer depth-reset warning. Legacy aapt dump badging could not read an android:required attribute; successful XML-tree inspection and aapt2 were used instead. aapt2 exits 0 but warns that the template's themed_icon.xml reference is missing. The same warning exists in the earlier M0 APK. Signatures/native contents pass; launcher behavior on the new physical build remains untested.

**MCP remains partial/failed**, not passed: the tagged bridge can reload a changed open script, but a later editor save restores the old text buffer. The M1 pinned-source inspection is consistent with the existing failure and is not a new successful smoke. See [MCP evidence](../docs/mcp-smoke.md). Independent command-line checks continued.

The player's earlier successful M0 Thor report is preserved, but does not establish all detailed M0 metrics or the later placement follow-up. M0 physical performance/thermal/placement evidence remains open, as do documented per-edit native mesh acknowledgement and release-memory telemetry limitations. See [M0 report](M0-platform-spike.md) and [placement follow-up](M0-placement-followup.md).

**Not run:** M1 physical Thor controller regression, sustained sculpt/render/save costs, thermals, device launcher/update behavior and player visual approval. The overlay cannot provide an unavailable native per-revision completion acknowledgement. Use the [seven-step Thor checklist](../docs/M1-thor-playtest.md), including cold restart and held-input interruption checks. Terrain scale and controller feel require that feedback.

Stop here for the M1 handoff. Neither M1 completion nor catalogue expansion is declared.
