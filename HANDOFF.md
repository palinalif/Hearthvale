# Hearthvale — current M1 handoff

Updated 2026-09-08. Read AGENTS.md and the current user message first. The user approved implementing direct cottage resize handles and manual-window stability, followed by graphical UI polish. M1 is not complete. The Thor-accepted comparison build remains `c54d0559`; the new resize candidate requires its own focused physical retest.

## Branch and candidate

New branch: `feat/m1-direct-resize-handles`, based on acceptance record `0ced5929234a5268d6e0f164e115887ddd501d33`. `master` and the accepted repair branches are untouched. Candidate: `f90c884036cd26b845bad8ae68722cdbebb09788`. Subsequent documentation-only commits do not change its APK.

Small commits:
- `82f4e98556573d496bf4efd5c386a04f3c487ecc`: one-sided authoritative bounds transaction, anchor compensation and model regressions.
- `95cf7c9766ce4f8abcadf96e2d46bfa804eccc6b`: controller-picked side/corner/top handles, previews and full-scene/render regression coverage.
- `f90c884036cd26b845bad8ae68722cdbebb09788`: correct entry hint and hide the idle pointer during a grabbed-handle action; restore it on cancel.

## Implemented interaction

`scenes/m1.tscn` now uses `scripts/m1_scene_resize_handles.gd`, extending the accepted `m1_scene_thor_retest.gd`. Visible-facing sides/corners and a handle above the roof are drawn without relying on an icon font. Hover highlights a specific handle and shows A Grab. A grabs, LS drags relative to the camera, A commits, B restores while staying in Building. RS orbit, trigger zoom and R3 reframe remain available; L3 changes precision. Bare-shell A no longer enters the old axis-selector resize action. Detail A-move and X-options remain inherited. Old floating resize cubes are hidden.

Side drags fix the opposite edge; corner drags fix the opposite corner; height changes keep the base and footprint fixed. The live selected-cottage preview includes changed transform and dimensions. No authority/history mutation occurs before confirmation. Commit creates one building transaction; undo/redo restore bounds and anchors together. Pause cancels the preview and stale-revision changes are rejected. Stationary previews do not rebuild meshes repeatedly.

`scripts/cottage_resize_world.gd` subclasses the existing BuildingWorld model using the same document/schema/ID/history/recovery implementation, rather than introducing another model or save format. Local origins shift during one-sided sizing; authored surface/fixed-local anchor positions and matching overrides are compensated so manual windows keep their wall-tangential world position and height. They follow their own supporting wall along its normal when that wall moves. Suppressed/moved exclusion anchors and unsupported attachments are retained; automatic windows still reflow through the original model.

Precision horizontal steps are 0.25 world units (two visible cells), height steps 0.125 (one cell); normal steps are double. Horizontal paired cells deliberately keep the shifted origin in the existing renderer's grid phase, preventing half-cell window drift. Do not claim single-cell horizontal sizing. World cell size remains 0.125, miniature scale and engine/dependency/schema settings remain unchanged.

## Evidence

Complete run: https://github.com/palinalif/Hearthvale/actions/runs/34233812865

Gameplay/render job `102086289710` and APK job `102087134842` both succeeded on f90c8840. The 11 existing M1 integration suites passed, as did targeting (54), prior repairs (60), settings (14), renderer stability (35), D-pad recovery (15) and terrain navigation (21). New model/anchor checks: 70; new complete-scene controller checks: 30; all zero failures. Model tests cover rotated cottages, opposite-edge/corner anchoring, manual window world and rendered position, pane size, overrides/suppression, other-cottage isolation, preview purity, one-step undo/redo, stale revision rejection, shrink/recovery/growback and same-schema reload. Controller tests exercise real A/B/D-pad/Start/L3 and stick events through the exported scene.

Actual Mobile/D3D12 software rendering passes 71 checks and writes 13 captures, including the existing exact two-cottage colour-cancel image equality and the new resize previews. Initial candidate 95cf7c97 also passed; its captures exposed a misleading entry toast and an idle crosshair during handle drag. f90c8840 fixes both and adds rendered-path checks. The final active-handle screenshot was visually inspected; there is no physical Thor approval or quantitative handheld frame-time measurement yet.

Final diagnostic/source artifact `10059034388`: downloaded archive SHA256 `63df89a54bb76923a119beaae0a98e555ccfc8506e72a7f1bf0d7e394f00ef05` verified. The two final modified sources match the published source archive after normalizing CRLF/LF. Native runtime readiness and pixel equality gates remain unchanged; the render process wall-clock budget is 180 seconds to accommodate the additional five captures.

Both the initial implementation and any candidate claims must be grounded in the actual run logs. Tests and software Mobile captures are not physical Thor performance or user visual approval. No native Godot runtime or independent reviewer was available in the editing container; no independent review is claimed. Existing gameplay checks and exact colour-cancel pixel comparison must not be weakened.

## Delivery and installation

APK artifact `10059081903`: downloaded archive SHA256 `b3664981905b0825a12df3d46c4945f9103df42bab889c0d366785d360ddd88d` verified.

Extracted APK `hearthvale-m1-repair-f90c8840.apk`: 37,777,816 bytes; SHA256 `bef231fc8118cedc03f39431677d737dcbdbb2ae15a6cb87505e5e2cf82931f6`, locally matched against the CI verification receipt. CI verifies package/version, signature, Mobile metadata, ARM64-only architecture and byte-identical pinned native voxel library; development resources are excluded. Local ZIP inspection additionally confirms compiled resize scene/model/overlay, accepted terrain-retest layer and inherited repair layer are included.

Private Drive APK: https://drive.google.com/file/d/1pErUFuKdPhF9L7y79tYdWNfWV1HgPUnW/view

Private Drive checklist: https://drive.google.com/file/d/1PuYcjC9ymfhUoKbgVGBDys1PqPfknf0u/view

Both uploads were read back as expected name/MIME/size and shared=false (APK 37,777,816 bytes; checklist 3,874 bytes). Drive's normalized metadata did not return requested checksum fields; no remote checksum comparison is claimed. The extracted APK was uploaded, not its archive. Older artifacts and saves remain untouched.

The candidate installs as **Hearthvale Test f90c8840**, package `org.hearthvale.game.repair.cf90c8840`, version code 6 / `0.1.3-repair-f90c8840`. It is a separate fresh test valley. Keep all existing apps and saves; nothing is replaced, migrated, cleared or uninstalled. Permanent signing continuity remains unresolved; commit-specific isolated package identities and ephemeral CI keys are a temporary delivery mechanism. No private keys are uploaded.

## Accepted baseline and remaining work

Preserve the player's accepted `ca5185dc` cottage repair interactions and all-green `c54d0559` camera/D-pad follow-up: specific-cottage X entry, visible-window A-move/opening alignment, action-first B restore/exit, color/variation isolation across two cottages, no previous Z-fighting, camera-facing attachments, recovery, duplication camera, wrong-context prompt isolation, reload/immediate sculpting, same-app save/relaunch, gentler per-tool strength and faster settings. Terrain camera does not chase sculpted height or cling to a summit; D-pad recovery no longer needs a left-stick workaround. Do not relabel those old accepted checks as untested.

1. Focused resize retest: visible/hittable handles on Thor, screen-relative drag direction (including low angles), opposite-edge anchoring, preview/confirm/cancel, resize performance, manual-window/render alignment, recovery and one-step undo. Use the new checklist; do not repeat every unchanged accepted test.
2. After resize usability acceptance, graphical tool icons, coherent HUD/panels, typography and focus states as the user requested. Preserve the already accepted controller grammar and uncluttered miniature presentation.
3. One-block overhang targeting and Slope performance/plane-guide clarity remain open. This resize work does not resolve them.
4. Higher-detail cottage prototype and later tree/river refinement. No M2.
5. Stable securely retained Android signing and deliberate save migration before routine in-place updates.
