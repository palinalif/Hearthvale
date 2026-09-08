# Hearthvale — current M1 handoff

Updated 2026-09-08 after the player's all-green physical c54d0559 camera/D-pad retest. Read AGENTS.md and the latest user message first. **Core cottage interactions and the camera/D-pad repair follow-up are now accepted on the Thor for the reported checks. c54d0559 is the accepted repair baseline. M1 is not complete.**

## Physical baseline — preserve what passed

The user tested `hearthvale-m1-repair-ca5185dc.apk` and passed specific-cottage hover/X entry, visible window targeting, deliberate A-move in both axes with the opening following, move/style cancellation, idle B exit, crosshair/reticle isolation, visible-side-only picking, two-cottage edit/colour isolation, variation/colour pickers and recolouring without the earlier Z-fighting. Attachment placement and recovery, duplication camera, prompt isolation, reload/immediate sculpting, same-app save/relaunch, per-tool strength defaults/memory and brush settings also passed, with two exceptions at that checkpoint.

Historical exceptions in ca5185dc: the Needs placement entry required left-stick navigation rather than D-pad; Raise while moving the brush remained jumpy and biased toward the highest point. BOTH exceptions passed the user's subsequent focused physical c54d0559 retest below. Do not reset accepted interactions to untested or describe these two resolved exceptions as current failures. Original source-derived feedback and implementation hypotheses remain in `reports/M1-ca5185dc-device-retest.md`; its pending-CI paragraph records a historical checkpoint, superseded by the completed evidence here.

## Physical c54d0559 acceptance — 2026-09-08

Source: the user's latest completed checklist in this conversation, concluding “ALL GREEN LET'S GOOOO”. All eight items were marked passed:

- Hold Raise in one place, release, and wait: terrain grows without the camera rising with it or jumping upward on release.
- Hold Raise while travelling horizontally: horizontal movement, orbit and zoom remain available without terrain growth dragging camera elevation upward.
- Release Raise and move off the hill: the brush reacquires lower ground at its new position without sticking to the summit or jumping sideways to a nearby peak; camera elevation eases down without snapping.
- Repeat with Dig and B cancellation: no camera jump during the edit, on cancellation or after release; undo/redo continue to affect the edit normally.
- Travel over uneven ground, then enter/exit a cottage: accepted cottage orbit, duplication camera and B-exit view preservation remain unchanged.
- Navigate the cottage menu entirely with D-pad: Duplicate → Add flower box → Add shutter → Material → Needs placement → Close; Up reverses that order.
- Open Needs placement with A; with two displaced details, D-pad Up/Down selects each and A picks up the highlighted item, without a left-stick workaround.
- B cancels recovery without deleting the item; reopening and A-placing it removes it from the recovery list.

This is player-reported physical acceptance of these behaviours, not new quantitative frame-time measurements, exhaustive QA or completion of the remaining M1 scope. Preserve these results as the baseline for future work. Do not ask the player to repeat the entire accepted cottage checklist for unchanged code.

## Accepted candidate and commits

Branch: `fix/m1-terrain-camera-retest`, based on `f264d7a80f7304286e634b965abe37b05b0e3e9f`. Existing repair branch and `master` were not changed by this follow-up or acceptance record.

- `7935f97afb16bad81ff0f941ef7e7376b42dd758`: D-pad focus follows the displayed cottage menu order and skips unavailable controls. Includes complete-scene physical-button regression.
- `c54d055937d450198ce219027c7a5a6473883a90`: independent terrain-camera elevation and exact-column ground reacquisition during navigation, plus regression and CI integration. This is the APK the user accepted.

The exported scene uses `scripts/m1_scene_thor_retest.gd`, extending the accepted `m1_scene_playtest_repair.gd`. It does not replace the inherited native sculpt/preview, cottage, recovery, history or save implementations. Subsequent documentation-only commits do not change the delivered APK.

The previous camera eased toward cursor height even though stroke commit moves the cursor to the raised/dig frontier. The follow-up holds camera elevation during sculpting and after commit/cancel while retaining X/Z movement, orbit and zoom. Between strokes, deliberate Ground-reference travel samples the current native column rather than a neighbouring peak; camera height eases toward that navigation goal with a 3 world-unit/second cap. Wall/Ceiling and active-stroke targeting remain independent. This is a bounded native column probe, not a heightmap or full-world scan. The reported camera-comfort checks now passed physically; quantitative device performance remains unmeasured.

## Completed automated validation and artifact

Complete successful CI: https://github.com/palinalif/Hearthvale/actions/runs/34227414816

Gameplay/render job `102064828684` and APK job `102065561917` both succeeded. Existing 11 M1 integration suites and the previous targeting/repair/settings/stability gates passed. New `m1_recovery_dpad_test`: 15 checks, zero failures. New `m1_terrain_navigation_test`: 21 checks, zero failures. The latter actually grows native terrain, tests camera height while held and after release, travels onto lower ground, checks preview column/height, bounded camera movement, history isolation and cottage-exit view preservation. Mobile/D3D12 render gate: 41 checks, zero failures, including exact two-cottage colour-cancel image restoration. These remain CI results, separate from the player's subsequent physical acceptance above. No local Godot runtime was available. This documentation-only acceptance update does not rerun tests or produce another APK.

Diagnostic/source artifact: `10056379421`, SHA256 `075cbb5054eab265675a621a138ab048491268d320e37d0788aa65fbceb12984` (download verified).

Verified APK artifact: `10056427326`, archive SHA256 `8a46baf147b756cbf16dc0894d244083d3e3952ef14556bfcf7e76cbf7851dc6` (download verified).

APK `hearthvale-m1-repair-c54d0559.apk`: **37,760,897 bytes**, SHA256 `5e4b040485d4ecec223f1038fd30c42261264738efcb9bf055ec287f828f1b13`. Extracted size/hash matched the CI receipt. Package, version, signature, Mobile metadata, ARM64-only architecture and byte-identical pinned voxel library passed. Locally confirmed both compiled `m1_scene_thor_retest.gdc` and the inherited repair script are in the APK.

Private Drive APK: https://drive.google.com/file/d/1Z3FpWEwEWfip9FUOtBviOfWGqRbMh-Fz/view

Private Drive short checklist: https://drive.google.com/file/d/1Np_mmOaZJO16cOvpH2fHiw2-PZbtfLvc/view

Both uploads were verified by metadata: expected name, MIME, size; shared=false. The connector did not return Drive checksums; do not claim a remote hash comparison. The extracted APK, not the ZIP, was uploaded. Existing artifacts remain untouched.

## Installation

Separate test app: **Hearthvale Test c54d0559**, package `org.hearthvale.game.repair.cc54d0559`, version code 6 / `0.1.3-repair-c54d0559`. It starts a fresh valley and does not replace the original or ca5185dc test app or migrate their saves. Never uninstall or clear old apps to bypass signing. The ephemeral CI key and commit-derived package remain a temporary isolated delivery mechanism, not stable signing continuity.

The focused retest is complete. Keep this APK and its test saves available as the accepted comparison build. No new build or merge is implied by this acceptance record.

## Remaining scope, in order

1. Direct side/corner/height resize handles and comprehensive manual-window resize/layout stability. Preserve accepted selection, movement, recovery and camera behaviour.
2. One-block overhang targeting, Slope performance and plane-guide clarity. These were not solved or accepted by the idle navigation column probe or this focused retest.
3. Graphical HUD/panel/controller-glyph polish, then higher-detail cottage prototype; river/tree refinement later. No M2.
4. Stable securely retained Android signing and deliberate save migration before normal in-place updates.

Pinned Godot 4.7.2.stable.official.ed1daf0bf, native Voxel Tools, .125 visible grid, miniature scale, world size, schemas and permissions remain unchanged. Preserve IDs/manual overrides, unsupported attachments, native caves/overhangs, transactions/cancellation, player saves and previous APKs. The reusable APK workflow remains gated on regression/render success and strict verification. Do not weaken gates to produce a green build.
