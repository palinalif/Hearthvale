# M1 Astra visual rework handoff

Status: implemented review candidate, 2026-09-06. The prior visuals were explicitly rejected. **Player visual approval is pending; M1 is not declared complete.** No M2 work was started. The Thor was not connected (zero authorized ADB devices); all new physical checks are **not run**.

## Ownership and preserved game

The main Astra session directly designed, implemented, rendered, inspected and revised this visual rework. AGENTS.md and the active implementation plan now supersede mandatory Luna coding. Project-local `.codex/config.toml` explicitly selects `gpt-6-astra` / `high`; the existing MCP settings and permissions were preserved. Codex CLI is 0.153.1. Both TOML files parse successfully. The historical `luna_worker` remains genuinely `gpt-5.6-luna` / `high`, marked unauthorized for this rework; it was not renamed or silently substituted. No Astra subagents were used and no independent runtime model metadata was exposed. Earlier Luna controls/scale work was preserved and independently integrated.

The authoritative building recipe, IDs, overrides, suppressed details, manual attachments, recoverable orphans, duplication, undo/redo and combined checkpoint format remain intact. The native terrain backend, grid and generator data are unchanged; only terrain material colors changed. Continuous sculpting and controller fixes remain active. Loaded buildings keep their saved dimensions and transform. Fresh cottages now use 18 x 7 x 14 local dimensions at uniform 0.5 scale: a 9 x 3.5 x 7 world-unit wall volume, plus the roof. For an old full-scale save, use Cottage actions > Miniature scale; this is undoable and preserves dimensions/details. Adjust height using the existing resize controls if desired.

## What changed visually

The renderer now cuts real openings around the resolved editable windows. Recessed dark glazing, pale reveals/sills, mullions and open sage shutters replace flat glowing rectangles; moving, replacing or suppressing a window rebuilds its opening. Round replacements retain stepped surrounds. Manual flower boxes render as a trough, foliage and blossoms at the saved anchor.

Fine terracotta roof courses, segmented ridge caps, exposed eave joinery, foundation courses, a stepped entrance canopy and gable vent add depth. Incorrect triangle winding in the old custom roof batch was identified from the first render and corrected. Repeated components now use native cube instancing, while cut walls use generated meshes. All detail geometry is disposable output of the existing recipe, independently scaled from terrain cells; no decorative voxel is simulated as a terrain block.

Five taller asymmetric voxel crowns, clustered underplanting, narrow stepping slabs, planted beds and stone/reed bank accents connect the cottage to its immediate surroundings. Rooted scenery resamples native terrain after edits and hides when support cannot be found. Warm directional light, stronger cool ambient fill and a coherent plaster/terracotta/sage palette replace the muddy fogged blockout. No external production assets were used.

## Actual render inspection and iterations

The official [Town to City](https://store.steampowered.com/app/3115220/Town_to_City/) and [Station to Station](https://store.steampowered.com/app/2272400/Station_to_Station/) gameplay imagery was visually inspected, not merely named. Town to City supplied architectural layering and garden composition cues; Station to Station supplied fine stepped roofs, foliage silhouettes and landscape palette cues. Tiny Glade remains the interaction reference, and the supplied screenshots remain geography references. No reference-game systems were added.

All captures below are the actual playable Godot scene using **Forward Mobile / Vulkan**, 1280 x 720, on the desktop GPU. MovieMaker was used for repeatable screenshots, not performance claims. Review flags use isolated temporary checkpoint roots and never overwrite player saves.

| Stage | Capture | Inspection and response |
|---|---|---|
| Before Astra | [Normal](screenshots/m1-controls-cottage.png), [close](screenshots/m1-controls-close.png) | Dark slab-like roof, buried trim, glowing panes, tall blank end wall, tiny isolated foliage. |
| Iteration 1 | [Normal](screenshots/m1-astra-iteration1.png) | Roof faces and window depth corrected. Still too tall and isolated; changed fresh proportions and rebuilt vegetation/composition. |
| Iteration 2 | [Clean normal](screenshots/m1-astra-iteration2.png) | Better scale/palette, but entrance bare and shrubs too evenly spaced; added bracketed canopy, gable joinery and grouped planting. |
| Iteration 3 | [Close](screenshots/m1-astra-close.png), [resized](screenshots/m1-astra-edited.png), [moved-window side](screenshots/m1-astra-edited-front.png) | Checked actual 23 x 8 x 12 resize and fixed-position moved window through BuildingWorld APIs. Beds remain rooted separately; this is visible and recorded below. |
| Final optimized geometry | [Clean normal](screenshots/m1-astra-final.png), [clean edited close-up](screenshots/m1-astra-final-edited.png) | Inspected again after instancing optimization; detail retained. HUD/debug hidden; gameplay target cue remains visible. |

Before/after normal views use the same yaw, pitch, FOV and distance. The final edited close-up uses the opposite side so the moved window is visible. [Dig](screenshots/m1-controls-dig.png), [near](screenshots/m1-controls-near.png), [far](screenshots/m1-controls-far.png) and [occluded](screenshots/m1-controls-occluded.png) control captures are retained from the integrated controls pass before the Astra art replacement.

## Tests actually run

`./tools/check.ps1` passed the full suite after the art replacement: native dependency probe/import; M0 checkpoint 38 checks plus cold-process fixtures; M1 checkpoint 23 plus cold-process fixtures; native backend 83; sculpt 116; scaled M1 backend 27; building record/render tests; M0 and M1 controller tests; new visual geometry 6; full M1 joypad acceptance 112; a second 112-check write-fixture run and 7-check cold read. Final aggregate log: `reports/logs/astra-full-check-final.log`.

After the performance optimization, building/render tests, all 6 visual geometry tests and the full 112-check controller acceptance were rerun and passed (`reports/logs/astra-acceptance-instanced.log`). The complete cold checkpoint suite was not repeated after that geometry-only optimization. Actual final Mobile captures and exported runtime smoke checks were also rerun.

The acceptance scenario exercises moved/replaced/suppressed windows, a manual flower box, widening/shortening/material changes, undo/redo, save/reload, independent duplication, shrinking past attachments, deleted support and recovery, stale results, cancel, continuous terrain actions and input gating. The added geometry tests ray-check actual window openings before/after moving/resizing/suppressing and check custom mesh winding against outward normals.

Failures found and addressed: earlier new test parse/type errors; raw airborne cursor passed to a grounded Dig preview (fixed by immutable stroke aim offset); a real pause-menu reload exposed integer versus JSON-float test comparison (all persisted design fields now normalized to the same JSON representation); incorrect roof face winding. The strengthened runner rejects FAIL lines and incomplete acceptance runs without a passing final JSON result.

## Desktop measurements, not Thor results

Pinned desktop: Windows 11, Ryzen 7 2700X, RTX 3070. Actual Mobile renderer, 1280 x 720, VSync disabled, 60 fps cap; 120 warmup frames, 180 idle, 180 sculpt, 120 consecutive dimension changes. No competing Godot checks during each profile. These are short editor-runtime measurements; frame pacing includes the cap.

| Phase | Frame p50 | Frame p95 | Max | Draw calls | Render primitive monitor |
|---|---:|---:|---:|---:|---:|
| Idle | 16.661 ms | 16.700 ms | 17.298 ms | 282 | 604864 |
| Sculpt | 16.661 ms | 17.025 ms | 19.284 ms | 281 | 598136 |
| Continuous resize rebuild | 27.965 ms | 32.799 ms | 41.159 ms | 282 | 566392 |

Rebuilding every detailed vertex in GDScript initially cost **72.266 ms p95** in presentation CPU time. Roof instancing reduced it to 42.965 ms; instancing the other repeated joinery/courses reduced it to **28.013 ms**. Geometry was retained rather than removed on an unmeasured mobile assumption. Resizing still exceeds a 60 fps frame budget on this desktop and needs further profiling/Thor feedback. Primitive counts are the rendering monitor, including passes, not unique authored triangles. Godot static memory was approximately 87.5-87.8 MB; this is not total process/native/GPU memory or a long-session leak test. [Machine-readable profile](m1-rework-desktop-profile.json).

## Builds and dependencies

`./tools/build.ps1 -Windows -Compatibility` produced all Android debug/release/Compatibility APKs and Windows equivalents. `python tools/verify-m1-apks.py` verified version code **4**, name **0.1.1-m1-rework**, package `org.hearthvale.game`, renderer metadata, ARM64-only libraries with exact pinned native hashes, compiled M1 scene, exclusion of development tools/MCP/tests/docs, signatures, and the same certificate as the archived first M1 build. Signing identifiers/keys are not included in reports. [APK hashes and checks](m1-rework-apk-verification.json).

- Recommended physical review: [Mobile debug APK](../builds/hearthvale-m1-debug.apk).
- [Mobile release APK](../builds/hearthvale-m1-release.apk), [Compatibility fallback APK](../builds/hearthvale-m1-compatibility.apk).
- [Windows debug](../builds/hearthvale-m1-debug.exe), [Windows release](../builds/hearthvale-m1-release.exe), [Windows Compatibility](../builds/hearthvale-m1-compatibility.exe). Keep each EXE with its PCK and the included voxel DLLs.

All three exported Windows programs ran 120 frames in isolated review worlds with exit 0 and no script/runtime errors. Mobile builds reported Vulkan Forward Mobile; the fallback reported Compatibility. [Windows verification](m1-rework-windows-verification.json). Android installation/launch was **not run**.

Dependencies are unchanged: Godot **4.7.2.stable.official.ed1daf0bf** and matching official 4.7.2 export templates; Voxel Tools **GDExtension v1.7x**, commit **75d3c6d996ed2331c80edcd8c3ebc947afc0f041**; Temurin **17.0.19+10**; Android build-tools **36.0.0**; development-only Godot AI MCP **3.2.5**. Exact source/archive hashes remain in `dependencies.lock.json`.

The existing aapt2 themed-icon warning remains (also present in M0); package verification succeeds, but physical launcher appearance is not claimed tested. Godot MCP remains **blocked/partial**, with the previously documented editor script-buffer persistence failure unresolved; it was not retested or marked passed. Command-line checks continued independently. See [M0 evidence](M0-platform-spike.md) and [placement follow-up](M0-placement-followup.md).

## Remaining gaps and physical review

This is substantially revised playable art, not a claim to match the reference games fully. The river is still a straight channel, the pad has abrupt geometric boundaries, the entrance gable remains relatively plain, and the foliage/bed repetition can be refined. Terrain-rooted garden beds and the path do not resize with a building and can intersect an expanded footprint; they are not saved building attachments. The editable attached flower box does follow its saved anchor. No static screenshot-only replacement was introduced.

On Thor, update with `adb install -r builds/hearthvale-m1-debug.apk` only when the device is authorized; do not uninstall or erase saves. Check:

1. Load your existing design; use Miniature scale for an old full-scale cottage, then test the height handle. Confirm manual edits persist.
2. Switch Terrain/Cottage, select Dig and Raise, verify the visible target matches the changed terrain and cannot resize the cottage. Check near/far/occluded aiming, cancel, undo and held-input menu/disconnect safety.
3. Move/replace/suppress a window, add a flower box, resize all axes, shrink past a detail, recover it, undo/redo, save/restart and duplicate.
4. Judge the new normal-zoom cottage/riverbank and close details. Visual approval remains yours.
5. Measure frame pacing during sculpt/resize, sustained thermals and memory. New physical Thor results, M0's outstanding detailed device metrics and native per-revision mesh acknowledgement remain unavailable/not run.

Stop here for M1 review; no M2 or expanded catalogue authorization is inferred.
