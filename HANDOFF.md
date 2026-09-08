# Hearthvale — current M1 handoff

Updated 2026-09-08. Read AGENTS.md and the current user request first. The user reports the f90c8840 resize build feels pretty good and asked for A on the house to offer Move house or Resize house, with handles appearing only after choosing Resize. This refinement is implemented and a verified candidate is uploaded for physical testing. M1 and the graphical polish pass are not complete.

## Current branch and candidate

Branch: `feat/m1-house-move-resize`, based on `e5c7f1fe61ffdfdb9920345a4863910206a2bd96` from the resize branch. Candidate: `44ebca5b124a1a3375d94fe5135c07cce07353f9`. Subsequent documentation-only commits do not change the APK. `master`, the previous resize branch and accepted repair branches remain untouched.

Small commits:
- `ff87b93cfc9846158e119bd2c393e5dac25c107a`: existing-house translation transaction with stable identity, stale-revision guard and undo.
- `07d6ef7baf4baaa48f7cef17f705a78e3026bf39`: bare-shell A chooser, opt-in resize handles, whole-house ghost relocation and cancellation.
- `84a85ff54fad0143a509b6c22444869bce072a1b`: complete-scene controller, save and rendered-cancel regressions; required CI integration.
- `e23300b860255ad0860dadba4a57ddd427a4bef1` and `44ebca5b124a1a3375d94fe5135c07cce07353f9`: correct the new JSON roundtrip comparison while retaining exact saved records, all resolved fields, positions and identities. No persistence runtime code changed in these two commits.

## Implemented interaction

The exported scene now uses `scripts/m1_scene_house_actions.gd`, extending the existing resize-handles scene, which retains the accepted terrain and cottage repair layers. This is a temporary action within Building, not a new top-level mode.

In Terrain, X on the hovered cottage still enters editing; A remains the terrain action. In normal cottage editing, resize handles are hidden. A on a bare selected house wall/roof opens a compact two-choice Move house / Resize house panel. D-pad Up/Down chooses and A confirms; B closes just the panel. Ordinary detail A-move and X-options remain direct, and A on empty ground does not open house actions. X cottage options, including Duplicate, remain available separately.

Move house relocates the EXISTING cottage, not a duplicate. It reuses the accepted free-placement camera/input/ghost path but commits only the existing record's transform position. The ghost starts at the original position rather than the duplicate offset, and temporarily replaces the opaque source renderer. IDs, local anchors, details, colours, dimensions and other cottages stay unchanged. X/Z displacement is snapped relative to the existing origin on the 0.125 grid, with pre-snap stick accumulation and rotated-footprint bounds. A commits one undo transaction; no-op confirmation adds none. B restores the unchanged document and source orbit. Pause/focus-loss cancellation and stale-revision cancellation restore the source renderer; a stale move cannot overwrite newer edits. This task does not add house rotation or a new terrain-grounding policy.

Resize house reveals the existing side/corner/height handles without automatically grabbing one. A grabs the pointed handle, LS drags, A applies and B restores the current drag. When choosing a handle, B finishes resizing and hides handles while staying in cottage editing; another B exits to Terrain. Existing opposite-edge/corner anchoring, base-fixed height changes, manual-window compensation and unsupported-attachment recovery remain intact. The resize model shares the existing schema/history, with no save-format replacement.

## Verification and unsuccessful iterations

Complete successful CI: https://github.com/palinalif/Hearthvale/actions/runs/34237601560

Source commit 44ebca5b. Gameplay/render job `102099259079` and APK job `102100362758` both succeeded. All 11 existing M1 integration suites passed. Additional gates passed: targeting 54, previous repairs 60, settings 14, renderer stability 35, D-pad recovery 15, terrain navigation 21, resize model 70, resize controller 31, and NEW house actions 49 checks, all zero failures.

The new controller suite uses physical A/B/D-pad/Start/shoulder and stick events through the exported scene. It tests chooser priority/focus, blocked world input, opt-in handles, operation-first cancellation, preserved detail editing, stable house count/identity, preview purity, camera restoration, translation confirmation, other-cottage isolation, one-step undo/redo, save/load, no-op/stale/nonfinite rejection, pause restoration and the distinction from Duplicate.

Initial run `34236486907` failed only the new whole in-memory dictionary equality after save/reload (40 checks, one failure); run `34237001071` failed only the JSON-text comparison (49 checks, one failure). The actual saved building records, reloaded transform/dimensions and detail positions passed. Final diagnostics demonstrate live automatic-layout metadata `{"version":1}` versus loaded `{"version":1.0}`. The final test normalizes BOTH complete views through JSON parse before comparison without dropping any fields or adding a geometric tolerance. Exact serialized raw building-record comparison and separate resolved transform/detail checks remain. No saving code was changed to address these assertion errors.

Actual Mobile/D3D12 software rendering passes 91 checks and writes 17 captures. It preserves the accepted exact two-cottage colour-cancel equality and adds exact image restoration after whole-house move cancellation, the two-choice panel and relocation ghost. The actual chooser and move-ghost captures were inspected. No physical Thor test, quantitative handheld performance measurement, local Godot execution or independent review is claimed for this candidate.

Diagnostic/source artifact `10060652880`: archive SHA256 `a134a5197ce89fe8a0658e968d33d54ec9cc83ff83f322621fa11d195ecb3568`, verified locally. All eight changed source/test/workflow files match the exact published source archive after newline normalization. Runtime native readiness deadlines, strict error receipts and existing pixel equality gates were not relaxed.

## APK delivery

Verified APK artifact `10060771655`: archive SHA256 `62883849c743cd379dae0f9ff567033d08e7d5a2f1b237e8b91ebdec672e95c9`, verified locally.

Extracted file `hearthvale-m1-repair-44ebca5b.apk`: 37,786,187 bytes; SHA256 `8472759dde89381e8c8963c4f07a6dad188608d043af3bb43d1deb34770ccef1`. Its size/hash/commit matched the CI receipt. CI verifies package/version, signature, Mobile renderer metadata, ARM64-only architecture, byte-identical pinned native voxel library and exclusion of development resources. Local archive inspection additionally confirmed compiled house-actions, resize-handles, resize-model, terrain-retest and inherited repair scripts.

Private Drive APK: https://drive.google.com/file/d/1HbQ1Vd5vuMEBM_m_zXOFcT72cpPhVBbm/view

Private Drive checklist: https://drive.google.com/file/d/1akgcXywA6CEbsUi2sNsqKtO-ojLr_0ju/view

Both uploads were read back with the expected name, MIME, size and shared=false. APK size 37,786,187; checklist size 2,569 bytes. No Drive checksum readback was supplied, so no remote hash verification is claimed. The actual extracted APK, not its ZIP, was uploaded; old artifacts are untouched.

Install as **Hearthvale Test 44ebca5b**, package `org.hearthvale.game.repair.c44ebca5b`, version code 6 / `0.1.3-repair-44ebca5b`. It installs alongside old builds with a fresh valley. Existing apps/saves are not replaced or migrated. Never uninstall or clear them to bypass signing. Commit-specific package identities and ephemeral CI keys remain a temporary safe delivery mechanism, not permanent update-compatible signing. No private keys were uploaded.

## Preserve accepted work and remaining scope

The user explicitly accepted the ca5185dc cottage repairs and all eight c54d0559 camera/D-pad retest checks on Thor. Their latest f90c8840 feedback is positive qualitative resize usability feedback, not an itemized all-green resize checklist. Preserve accepted selection, visible-window movement, action-first B, colour/variation isolation, attachment recovery, duplication camera, terrain camera/navigation, reload and brush settings.

1. Focused physical retest of A on bare house -> Move/Resize, unchanged A on details, opt-in handles and B depth, actual whole-house translation/restore/undo/save, and explicit Duplicate still making a copy. Do not require repeating all unchanged accepted checklists.
2. Graphical UI polish next as the user requested: icons, cohesive panels, typography and focus states without scrambling the accepted controller grammar. Maintain discoverability of existing cottage cycling and camera shortcuts during the polish pass.
3. One-block overhang targeting and Slope performance/plane-guide clarity remain separate open issues.
4. Higher-detail cottage prototype and later river/tree refinement; no M2.
5. Stable securely retained Android signing and deliberate save migration before routine in-place updates.

Pinned engine/dependencies, 0.125 visible grid, miniature scale, world size and schemas are unchanged. Preserve native caves/overhangs, authoritative IDs/manual/suppressed/unsupported records, cancellation/history, player saves and prior APKs. Never weaken validation to obtain a green result.
