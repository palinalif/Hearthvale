# Hearthvale — current M1 handoff

Updated 2026-09-08 after the player's physical ca5185dc retest and the camera/D-pad follow-up export. Read AGENTS.md and the latest user message first. **Core cottage interactions passed on the Thor. Two reported exceptions received a new candidate; that candidate still needs physical testing. M1 is not complete.**

## Physical baseline — preserve what passed

The user tested `hearthvale-m1-repair-ca5185dc.apk` and passed specific-cottage hover/X entry, visible window targeting, deliberate A-move in both axes with the opening following, move/style cancellation, idle B exit, crosshair/reticle isolation, visible-side-only picking, two-cottage edit/colour isolation, variation/colour pickers and recolouring without the earlier Z-fighting. Attachment placement and recovery, duplication camera, prompt isolation, reload/immediate sculpting, same-app save/relaunch, per-tool strength defaults/memory and brush settings also passed, with the exceptions below.

Exceptions: the Needs placement entry required left-stick navigation rather than D-pad; Raise while moving the brush remained jumpy and biased toward the highest point. Do NOT reset the accepted cottage interactions to untested, or claim the remaining camera comfort issue is already device-approved. Detailed source-derived feedback and implementation hypotheses are in `reports/M1-ca5185dc-device-retest.md` (its pending-CI paragraph records the implementation checkpoint; the completed results below supersede that paragraph).

## Current candidate and commits

New branch: `fix/m1-terrain-camera-retest`, based on `f264d7a80f7304286e634b965abe37b05b0e3e9f`. Existing repair branch and `master` were not changed.

- `7935f97afb16bad81ff0f941ef7e7376b42dd758`: D-pad focus follows the displayed cottage menu order and skips unavailable controls. Includes complete-scene physical-button regression.
- `c54d055937d450198ce219027c7a5a6473883a90`: independent terrain-camera elevation and exact-column ground reacquisition during navigation, plus regression and CI integration.

The exported scene uses `scripts/m1_scene_thor_retest.gd`, extending the accepted `m1_scene_playtest_repair.gd`. It does not replace the inherited native sculpt/preview, cottage, recovery, history or save implementations. Subsequent documentation-only commits do not change the delivered APK.

The previous camera eased toward cursor height even though stroke commit moves the cursor to the raised/dig frontier. The follow-up holds camera elevation during sculpting and after commit/cancel while retaining X/Z movement, orbit and zoom. Between strokes, deliberate Ground-reference travel samples the current native column rather than a neighbouring peak; camera height eases toward that navigation goal with a 3 world-unit/second cap. Wall/Ceiling and active-stroke targeting remain independent. This is a bounded native column probe, not a heightmap or full-world scan. New-device performance and comfort remain unmeasured.

## Completed validation and artifact

Complete successful CI: https://github.com/palinalif/Hearthvale/actions/runs/34227414816

Gameplay/render job `102064828684` and APK job `102065561917` both succeeded. Existing 11 M1 integration suites and the previous targeting/repair/settings/stability gates passed. New `m1_recovery_dpad_test`: 15 checks, zero failures. New `m1_terrain_navigation_test`: 21 checks, zero failures. The latter actually grows native terrain, tests camera height while held and after release, travels onto lower ground, checks preview column/height, bounded camera movement, history isolation and cottage-exit view preservation. Mobile/D3D12 render gate: 41 checks, zero failures, including exact two-cottage colour-cancel image restoration. These are CI results, not physical Thor acceptance. No local Godot runtime was available.

Diagnostic/source artifact: `10056379421`, SHA256 `075cbb5054eab265675a621a138ab048491268d320e37d0788aa65fbceb12984` (download verified).

Verified APK artifact: `10056427326`, archive SHA256 `8a46baf147b756cbf16dc0894d244083d3e3952ef14556bfcf7e76cbf7851dc6` (download verified).

APK `hearthvale-m1-repair-c54d0559.apk`: **37,760,897 bytes**, SHA256 `5e4b040485d4ecec223f1038fd30c42261264738efcb9bf055ec287f828f1b13`. Extracted size/hash matched the CI receipt. Package, version, signature, Mobile metadata, ARM64-only architecture and byte-identical pinned voxel library passed. Locally confirmed both compiled `m1_scene_thor_retest.gdc` and the inherited repair script are in the APK.

Private Drive APK: https://drive.google.com/file/d/1Z3FpWEwEWfip9FUOtBviOfWGqRbMh-Fz/view

Private Drive short checklist: https://drive.google.com/file/d/1Np_mmOaZJO16cOvpH2fHiw2-PZbtfLvc/view

Both uploads were verified by metadata: expected name, MIME, size; shared=false. The connector did not return Drive checksums; do not claim a remote hash comparison. The extracted APK, not the ZIP, was uploaded. Existing artifacts remain untouched.

## Installation and retest

Separate test app: **Hearthvale Test c54d0559**, package `org.hearthvale.game.repair.cc54d0559`, version code 6 / `0.1.3-repair-c54d0559`. It starts a fresh valley and does not replace the original or ca5185dc test app or migrate their saves. Never uninstall or clear old apps to bypass signing. The ephemeral CI key and commit-derived package remain a temporary isolated delivery mechanism, not stable signing continuity.

Ask for focused retesting: hold/move/release Raise; travel off the hill onto lower ground; repeat Dig/cancel; reach Needs placement and choose between two displaced details entirely with D-pad/A/B. Spot-check the accepted cottage camera transitions. Do not ask the user to repeat the entire already-passed cottage checklist.

## Remaining scope

1. Physical acceptance of this camera/D-pad follow-up; retain all accepted cottage behaviour.
2. Direct side/corner/height resize handles and comprehensive manual-window resize/layout stability.
3. One-block overhang targeting, Slope performance and plane-guide clarity. These were not solved by the idle navigation column probe.
4. Graphical HUD/panel/controller-glyph polish, then higher-detail cottage prototype; river/tree refinement later. No M2.
5. Stable securely retained Android signing and deliberate save migration before normal in-place updates.

Pinned Godot 4.7.2.stable.official.ed1daf0bf, native Voxel Tools, .125 visible grid, miniature scale, world size, schemas and permissions remain unchanged. Preserve IDs/manual overrides, unsupported attachments, native caves/overhangs, transactions/cancellation, player saves and previous APKs. The reusable APK workflow remains gated on regression/render success and strict verification. Do not weaken gates to produce a green build.
