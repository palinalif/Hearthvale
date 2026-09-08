# Hearthvale — current M1 handoff

Updated 2026-09-08 after both checklists for the shared UI APK. Read `AGENTS.md`, the user's latest request, `reports/M1-apk2-playtest-followup.md` and `reports/M1-apk2-ui-playtest-followup.md` first. **M1 is not complete. Cottage editing and the full UI pass remain open; successful CI/export did not establish physical-device usability.**

This replaces the stale September 7 handoff that still described preview performance work as unshipped. That historical document is retained in Git at `bd96e53e3509245817b43a450d16213572d38139:HANDOFF.md`; earlier baseline history is in `docs/history/HANDOFF-before-terrain-ux.md`. Do not treat those historical next steps as current instructions.

## Build identity and current work

There are TWO shared APKs: `hearthvale-m1-terrain-ux-thor.apk` and `hearthvale-m1-ui-ux-thor.apk`. The cottage and full-UI checklists both refer to the second APK; the earlier suggestion of three builds was incorrect.

The shipped UI runtime baseline is `4b0e864cad510090e5384e59e70a763c7510d857` on `feat/m1-ui-ux-overhaul`. The current repair branch is `fix/m1-cottage-playtest-2`, with targeting code at `bd96e53e3509245817b43a450d16213572d38139`. Later commits in this update are documentation only. `master`, the shipped APKs, dependencies and save schema have not been changed by this workstream. Do not merge or publish a replacement from documentation-only progress.

The separate APK 1 follow-up on `fix/m1-terrain-strength-preview` was last reported at `821b254ac49b64ad5edc76095c72ac7c64bde7d6`. It is not integrated into this branch. Its latest CI/device status has NOT been checked in this documentation update. Inspect its actual code/tests and reconcile the inheritance chain deliberately before integration; do not overwrite `scenes/m1.tscn` with the terrain-only scene.

## Device findings to preserve

The user has physically tested both shared builds on the Thor. Terrain Dig/Raise/Smooth, preview usefulness and no noticeable hitching were positive overall. Requested exceptions: gentler Raise/Dig defaults (current level 3), keep Smooth's effective strength, target one-block overhangs reliably, and remove raising-camera jumps. The follow-up implementation is not itself device-approved.

For the UI APK, mode/tool clarity, D-pad switching/cycling, controller grammar, uncluttered presentation, terrain tools/settings, placement prompts, duplication basics and pause/save/hint settings were positive. Preserve those behaviours. Radius and strength adjustments need fewer button presses; do not dismiss menu use as user error. Cosmetic polish is a separate task after cottage details work.

Blocking issues: unreliable cottage/detail selection, no visible hover in the shipped APK, missing-glyph pointer, terrain reticle in Building mode, idle B not exiting, camera snap on exit, wrong attachment wall and snap sticking, inaccessible Needs Placement, render/style Z-fighting, manual-window/resize consistency, and duplication needing a free camera. Additional checklist: no-terrain target after Reload, terrain prompts when pointing at ground in Building mode, and laggy Slope with a confusing blue plane.

The blue rectangle is the intentionally retained Level/Slope target-plane guide, not evidence that the old generic footprint preview is still used. Guide clarity and Slope performance are separate issues. The user has still not successfully moved a window in the shipped build.

## Completed code patch, with evidence boundaries

`bd96e53` corrects the inverted outward wall-facing test, uses bounded projected detail footprints, replaces the font-dependent pointer with geometry, hides the terrain reticle in Building mode, adds a target outline/near-target A Move and X Options prompt, and guards stale detail hover ownership.

Windows CI run `34210362375`, job `102009628502`, passed the existing M1 integration gates and `m1_cottage_targeting_playtest_test` (54 checks, zero failures). These are automated/headless checks, not Android visual validation or Thor acceptance. No new APK was built from this repair patch in this workstream.

## Next implementation order

1. Add exported-scene reproduction for Reload -> Resume -> preview/sculpt and Building-mode ground-hover prompt isolation. Treat recovery/context safety as blockers, alongside the current cottage fixes. The inspection in the second report describes hypotheses, NOT established root causes.
2. Specific-cottage entry: Terrain hover highlights a cottage and shows X Edit cottage; X selects that exact building. A keeps terrain semantics. B cancels/closes an operation first and exits idle cottage editing. Preserve view on exit rather than returning abruptly to the old terrain camera. Make switching cottages discoverable.
3. Correct render/style ownership and Z-fighting. `_selected_visual_roots()` currently includes the first cottage renderer and selected renderer; style preview can rebuild both using the selected recipe. Test IDs/transforms and actual rendered state across preview/cancel/commit/undo and two cottages.
4. Start attachments on the camera-facing/hovered wall. Preserve an unsnapped movement accumulator so alignment cannot trap stick movement. Make Needs Placement reachable and operable with a controller. Free-camera duplication returns to original/new cottage orbit on cancel/place.
5. Direct side/corner/height resize handles, correct one-sided expansion, manual-window stability, and visual resize consistency.
6. Profile Slope separately from the other sculpt tools; retain truthful exact cell feedback. Refine its target-plane guide. Reduce radius/strength adjustment steps with visible direct controls and retained focus without silently changing accepted camera/history bindings.
7. Separate graphic HUD/panel/controller-glyph polish. Higher-detail cottages, river and tree iteration remain later; no M2.

## Implementation and validation contracts

Use small reviewable commits, native volumetric terrain and the approved miniature scale. Preserve authoritative IDs, manual overrides, suppressed details, transactional cancellation, recovery and one undo entry per committed edit. Keep controller-only single-screen use. Do not change pinned engine/backend, world size, libraries or save architecture to avoid a bug.

Run targeted tests on the COMPLETE exported scene, not only inherited historical base scripts. Add independent geometry/visibility expectations, two visibly different cottages, actual input routing and recovery after menu/context/reload transitions. Required new evidence and retest cases are detailed in both playtest reports. Obtain Mobile captures for hover, style, resize and recovery before visual claims. A green label-existence test is not UX acceptance.

No native Godot runtime was found in the editing container during this report update, and no tests were run for these documentation-only changes. Do not claim new performance measurements, a reproduced reload root cause or repaired ground-hover prompts.

## Saves and future APKs

Preserve all player/test/legacy saves and existing Drive artifacts. Never uninstall to bypass signing conflicts. Signing continuity with prior ephemeral CI debug keys remains to be established before a new update-compatible APK. Use a distinct versioned filename and commit/build identity; verify package, signature and native library; upload privately to the user's Drive only through the available tools and verify metadata afterward. Export, desktop render and Thor approval are separate results.

For the next device check, provide a focused changed-items checklist instead of repeating both long earlier checklists unchanged. Do not call the overhaul complete until the user can deliberately select a cottage, see a highlighted window, move it successfully, recover displaced details and resume sculpting after reload.
