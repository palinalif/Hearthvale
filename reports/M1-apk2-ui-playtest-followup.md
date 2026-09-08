# APK 2 — additional UI/UX playtest results, 2026-09-08

## Source, build identity and status

Source: the user's second checklist for the already shared `hearthvale-m1-ui-ux-thor.apk` (runtime baseline `4b0e864cad510090e5384e59e70a763c7510d857`). This supplements, rather than replaces, `reports/M1-apk2-playtest-followup.md`.

There were TWO shared build APKs, not three: `m1-terrain-ux` and `m1-ui-ux`. The earlier checklist incorrectly labelled its cottage and full-UI sections as separate APKs. Both sections belong to the SAME `m1-ui-ux` build. The targeting patch `bd96e53` was committed after this APK; the user's present results do not validate that patch.

This report-only commit changes no runtime code and publishes no APK. All defects below remain open unless a subsequent implementation receipt explicitly closes them. Do not confuse tests of older base scripts, successful export, or green CI with physical Thor acceptance.

## User-reported results, preserving the checklist categories

### First 30 seconds — no experimenting

Passed: understanding what to do without prior instructions; immediate mode and tool recognition; discoverable important controls; no sense of screen clutter.

### Terrain mode

Passed: D-pad Left/Right cycling, visible tool changes, Dig, Raise, Smooth, other terrain/foliage tools, X opening terrain settings, controller-only navigation, radius/strength/falloff adjustments, and closing settings to resume sculpting.

Exceptions: Slope was a bit laggy and still displayed a blue rectangle. The user instinctively went to the action menu to adjust radius instead of the shortcut they recalled, and expected graphic HUD elements with sensible placement to help. Later in the checklist they explicitly identified increasing/decreasing BOTH radius and strength as taking too many button presses. Do not dismiss this as merely needing practice.

### Mode switching

Passed: D-pad Up in both directions, appropriate HUD changes, repeated rapid switching, no stale mode/tool prompts noticed in that sequence.

Specific exception: hovering ground while in cottage editing showed terrain editing prompts. Preserve this report even though the general mode-switching checks passed. A ground hover must not implicitly change edit context or offer terrain actions in Building mode.

### Building mode

Failed: obvious cottage selection/editing and reliable access to cottage shell X-actions. Detail X-actions sometimes worked, without a visible highlight. Direct A-to-move remained unverified because of the targeting failures from the previous report. The user still had not successfully moved a window.

Passed: understandable duplicate/place and attachment placement flows, A-confirm/B-cancel placement prompts, and relevant precision prompts. No additional unqualified pass was given for the camera throughout this checklist; retain the camera successes AND transition/duplication complaints from the earlier report.

### Contextual HUD

Passed in tested cases: changing prompts for detail hover/movement, attachment placement and cottage placement; showing relevant controls; undo after edits and redo after undo; no prototype/debug clutter in ordinary play. The ground-hover context exception remains open.

### Pause/settings

Passed: pause, resume, save, settings, toggling contextual hints off/on, and B-as-back within menus.

Exceptions: after Reload, the game appeared to believe there was no terrain under the cursor. Needs Placement still could not be operated with the controller, so menu/focus acceptance is incomplete. B failing to exit idle cottage editing remains an exception to the general Back behaviour.

### Overall usability

The user reported that digging was intuitive and the controller grammar became predictable after roughly ten minutes. B failing to leave cottage editing was the only newly identified instinctive button mismatch. Radius/strength changes took more steps than expected. No other arbitrary controls were identified. The UI could be prettier, but the user explicitly preferred a separate visual-polish task AFTER cottage detail fixes. Editing all cottage sides and moving a window are still not usable enough.

## Triage and implementation acceptance

### Blocking correctness: reload target recovery

Reproduce on the actual exported scene: Save, change terrain/aim, Reload through the pause menu, Resume, then preview and begin/cancel/commit a sculpt stroke without R3 or manually changing modes to recover.

Test ordinary terrain, a changed-height brush position, small/large radius, a pre-reload pending preview and restored reference-plane state. Verify that the preview uses the restored voxel generation, not an old worker result; stale target state is invalidated and a valid local target can be reacquired. Also cover a genuinely empty location and an invalid/missing checkpoint: never manufacture a valid hit or erase/overwrite the current world on a failed load.

Inspection note, not a reproduced diagnosis: `m1_scene.gd::_reload_all()` loads the backend/document/landscape and clears edit histories, but does not explicitly reconcile the cursor, terrain target, reference state or preview lifecycle. The normal frame loop also performs target sampling, so the missing explicit reset alone does NOT establish the root cause. Investigate before patching. No evidence from this report establishes that the save itself lost terrain.

### Blocking correctness: Building HUD context isolation

Create a regression using the complete exported UI stack, with a selected cottage and the pointer over a detail, shell, ground, sky and another cottage. Building mode must remain Building mode until an explicit exit. Detail-less hover should show pointing/camera/exit controls, not Sculpt/terrain settings. Check every visible prompt surface (including toasts/reticles), not only the bottom bar.

Inspection note: both the terrain tool UI and base HUD explicitly inspect `view_context`; do not claim the issue is a proven missing context check without reproducing the complete interaction. HUD updates currently pass through several inherited presentation methods.

### Existing cottage blockers remain the main workstream

Retain the previous report's work: terrain-hover X entry into THAT cottage; idle B exits after cancelling/backing out of temporary operations; selected-cottage-only targeting and visible prompts; continuous camera transitions and free-camera duplication; render/style isolation and Z-fighting; camera-facing attachment starts; movement that escapes alignment snapping; controller-operable Needs Placement; direct side/corner/height resize handles and manual-window stability.

`bd96e53` is only the first targeting/reticle patch. It does not complete those other tasks. The separate APK 1 terrain follow-up is not integrated into this cottage branch.

### Terrain refinement: Slope

Profile idle preview, held sculpt calculation, native mesh updates and drawing separately at default and maximum radius. The prior no-hitch Dig/Raise/Smooth report is not evidence for Slope performance. Preserve exact preview/edit agreement, cancellation, connected-surface rules and history.

Design clarification from the code: Level and Slope deliberately retain `reference_plane` as a target-plane guide. It is distinct from the removed generic brush-footprint square. The guide still needs clearer presentation: propose a restrained labelled target-plane outline and slope direction/angle cues, while retaining the actual cell-change overlay. Do not simply remove useful plane information or silently substitute it for the affected-voxel preview. This presentation proposal has not been implemented or visually approved.

### Interaction efficiency: radius and strength

Keep the accepted overall mode/controller grammar. Improve common adjustments before calling the UI usable: a compact brush card with current Radius and Strength together, direct decrease/increase from a focused row, hold-to-repeat where safe, and retained focus rather than repeatedly navigating from the tool list. X settings remains a legitimate path, not something the player should be trained to avoid. Any shortcut must be visible and must not silently repurpose undo/redo or camera controls.

Inspection confirms `m1_scene_tool_ui.gd` currently builds separate Radius-/Radius+/Strength-/Strength+ action buttons and opens with focus on the first tool. This provides concrete unnecessary navigation to address. A final binding/layout has not been selected by this report.

### Later, separate visual polish

After cottage detail interaction/recovery works: consistent graphic controller glyphs, clearer brush-card hierarchy, spacing, focus/hover states and cohesive panel styling. Preserve the user's positive assessment of low clutter and immediate tool/mode comprehension. Do not begin higher-resolution decorative geometry to avoid solving interaction blockers.

## Next build evidence and retest scope

Use a versioned filename and commit identity rather than ambiguous APK numbering. Preserve the two existing Drive APKs and player saves. Do not publish another APK from this report-only commit.

The next focused device checklist should cover reload target recovery, no Building-to-terrain HUD leakage, specific-cottage X entry/idle B exit, visible detail targeting and a successfully moved window, style isolation, Needs Placement, revised placement/resize cameras, Slope cost, and fewer radius/strength adjustment steps. Keep passed controls as regression smoke checks rather than asking the user to repeat both long checklists unchanged.
