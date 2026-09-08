# Hearthvale — current M1 handoff

Updated 2026-09-08 during the M1 visual-finish work on `feat/m1-ui-polish`. Read AGENTS.md and the latest user request first. **The accepted M1 interaction lineage is merged into master; current visual work continues from that lineage on this feature branch.** The Thor-accepted gameplay baseline remains `44ebca5b`. M1 is not complete.

## Current visual-finish branch

The graphical UI, cottage-detail scale/variation, editable window and door, and in-world resize-handle passes are implemented on `feat/m1-ui-polish`. The latest environment pass replaces the straight presentation channel with a native-grid winding river and graded banks, changes the default scatter into deterministic planting drifts with deliberate cottage clearings, and gives the three tree variants broad orchard, tall riverside, and asymmetric wind-shaped silhouettes. It does not add a new catalogue or a water-editing system.

Fresh terrain uses the new river contour. Water is rebuilt from authoritative terrain cells after generation/load, so existing v2 saves keep water aligned to their original straight channel and are not rewritten by the new generator presentation. The focused riverbank gate checks a 2.25-unit centreline span, varying width, dry banks, the unchanged cottage pad, native-grid water geometry, upward winding, and old-save channel reconstruction. `tools/check.ps1` passes with this gate included; the actual Mobile vegetation/grid run passes 322,678 checks. Deterministic before/after captures are in `reports/screenshots/m1-riverbank-before.png` and `reports/screenshots/m1-riverbank-after.png`. Player visual approval and Thor performance remain open.

MagicaVoxel MCP is now available as a pinned, staging-only asset-authoring path. Codex registration is named `hearthvale-magicavoxel`; it launches commit `710671d49bdc89e4e3d1ff7c60541c1d0383ac16` through a private wrapper that rejects paths and confines all MCP writes to ignored `.tools/magicavoxel` folders. The upstream server requires `mcp==1.0.0`; its unconstrained requirements currently install an incompatible MCP 2.x API, so preserve the pinned environment/receipt under `C:\Users\Pali\.codex\mcp`. A new Codex task is required to discover the newly registered server.

The first protocol-level pilot called the real server, discovered 40 tools, generated six snapshots, and produced the project-authored `hearthvale_tree_pilot_broad.vox`. The reviewed source is copied to `assets/source/magicavoxel`; `vox_to_obj.py` removes internal faces and emits provenance, then `bake_mesh.gd` restores the exact 0.125 grid after Godot import. The candidate preserves four authored palette groups, contains 7,611 voxels / 6,968 triangles, and passes 25 headless asset checks plus 27 checks on the actual Mobile renderer. It is intentionally not wired into gameplay yet. The comparison capture is `reports/screenshots/magicavoxel-tree-pilot.png` (current tree left, MCP candidate right); player preference should decide whether to iterate, optimize, and integrate it.

The Drive delivery workflow now matches the deployed Apps Script contract: repository secrets `APPS_SCRIPT_WEBHOOK_URL` and `APPS_SCRIPT_WEBHOOK_SECRET`, plus the `GOOGLE_DRIVE_UPLOAD_ENABLED` switch. After every prerequisite gate and APK verification succeeds, CI resolves the authenticated GitHub artifact endpoint to a short-lived signed URL and sends only that URL and the webhook secret to Apps Script. The receiver downloads the ZIP and admits its APK/JSON receipt privately. Automatic delivery remains tied to `master` pushes; use `workflow_dispatch` on an explicit feature ref for a requested playtest APK. The 50 MiB artifact-archive ceiling is checked before notification.

## Master integration and evidence

PR #1: https://github.com/palinalif/Hearthvale/pull/1

Merged normally, without squashing or rewriting the individual commits, as `ceac17684ad1489d2cb91a6d640518a99b185c32`. Its parents are the old master `2da7b7e926b1ea73cbfa8418948160d52d7646aa` and integration head `5d382d879ab6106dbe48a09562fce8c2cc565996`. The PR contains 105 commits and 75 changed files. The merged tree `69d5a827ffd4c59fe4a9d674759dcceb4615b012` exactly matches the tested integration head. This handoff update is documentation only and does not change gameplay or require another player retest.

The accepted source branch `feat/m1-house-move-resize` at `8f6365cf80d8f422027f41e79b3501518dfa13d5` already contained the earlier UI/cottage/terrain-camera/resize work. It was 103 commits ahead of old master, zero behind; only HANDOFF.md changed after the player-tested `44ebca5b124a1a3375d94fe5135c07cce07353f9`. No runtime changes were added for integration. Existing feature/repair branches and APKs were preserved.

Do not independently merge the superseded terrain experiments in `fix/m1-terrain-strength-preview` or `fix/m1-terrain-feedback-20260907-review`. The accepted terrain implementation is already in the integrated scene. Experimental all-face overhang targeting is not implicitly accepted or newly included by this merge.

Integration-only commits:
- `7b2070287856eaabf6643b5455fbfcf9598f5bc3`: route the existing full cottage regression/render workflow to master pushes and PRs targeting master. APK export remains dependent on successful checks and is skipped for PR test-merge refs. Assertions, dependencies, permissions, runtime and signing configuration were not changed by this routing edit.
- `5d382d879ab6106dbe48a09562fce8c2cc565996`: update the standalone exported-scene Terrain UX test to the explicit player-approved Raise/Dig=3 and Smooth=5 defaults and current visible settings/HUD. Physical D-pad navigation replaces the legacy Strength+ test action; per-tool independence and retained adjustment are checked. Existing native preview, cache, reference-plane, cancellation and three-second preview-deadline checks remain.

The first PR Terrain UX run `34240238979` failed three obsolete expectations (uniform default 5, old strength-labelled HUD, and legacy 5-to-6 adjustment). Its native brush/smoothing/next-layer/occupancy/async/performance/live-preview tests passed. No gameplay code was changed to resolve these test-contract mismatches and no gate was bypassed.

All four PR workflows passed on integration head 5d382d8:
- Sculpt feedback: https://github.com/palinalif/Hearthvale/actions/runs/34240834934
- Terrain UX, including its Mobile bulk-render parity step: https://github.com/palinalif/Hearthvale/actions/runs/34240834950
- M1 attachment/placement/controller: https://github.com/palinalif/Hearthvale/actions/runs/34240834948
- Full cottage repair/resize/house-action and Mobile-render checks: https://github.com/palinalif/Hearthvale/actions/runs/34240835319

Post-merge gameplay and Mobile-render validation also passed on ceac176 in run https://github.com/palinalif/Hearthvale/actions/runs/34241299045 (gameplay/render job `102111846184`). APK export/verification is a separate dependent job (`102112974093`) in that run; check its actual final result before publishing any new artifact. The already delivered and physically accepted APK below remains the player's comparison build. No integration APK has been uploaded to Drive in this merge session.

## Physical acceptance — preserve what passed

The user accepted the ca5185dc cottage repairs and all eight c54d0559 terrain-camera/D-pad recovery checks on the Thor. Their f90c8840 feedback was positive qualitative resize usability feedback, not an invented itemized all-green checklist. After receiving the integrated 44ebca5b house-action build they confirmed: "yep, it all works as expected :) good job".

This is player-reported functional acceptance, not exhaustive QA or quantitative frame-time evidence. Preserve specific-cottage Terrain-hover X entry, visible-window A movement with its opening, direct X detail options, action-first B cancellation/exit, two-cottage colour/variation isolation, attachment placement/recovery, free-placement camera, stable terrain navigation, reload/immediate sculpting, per-tool strength defaults/memory and controller settings. Do not ask the player to repeat unchanged accepted checks.

## Current interaction and implementation

`scenes/m1.tscn` uses `scripts/m1_scene_house_actions.gd`, extending the resize-handles scene, the accepted `m1_scene_thor_retest.gd` terrain-camera/D-pad layer, and the inherited cottage repair/UI layers. Do not switch the exported scene back to a historical base script.

Terrain retains A sculpt and X to edit a hovered cottage; otherwise X opens terrain settings. D-pad Up remains the top-level context switch. In ordinary cottage editing, A on a bare selected wall/roof opens Move house / Resize house; a detail keeps direct A-move and X-options. Window and door options include Resize and Colour; left stick changes width/height, A commits, B restores and L3 selects fine increments. The door is a stable attachment whose opening and porch follow movement and size. D-pad chooses, A confirms, B closes the chooser. Empty ground does not trigger house actions or terrain prompts while editing a cottage.

Move house relocates the existing record, not a duplicate. The wall details, IDs, colours, dimensions and local anchors remain with it. A ghost temporarily replaces the opaque source; free-placement camera/input are reused. A commits one undo transaction, B restores the source and its orbit, and no-op confirmation adds no history. Pause/focus-loss/stale-revision cancellation cannot overwrite newer edits. Explicit Duplicate remains distinct. This work did not add house rotation or a new grounding policy.

Resize is opt-in: choosing Resize reveals the side/corner/height handles without grabbing one. A grabs, left stick drags relative to the camera, A applies, B restores the current drag. Between drags B hides handles and stays in cottage editing; another B exits to Terrain. Right stick orbit, trigger zoom and R3 reframe remain; L3 controls precision.

Side/corner sizing holds the opposite edge/corner fixed; height keeps the base/footprint fixed. `cottage_resize_world.gd` retains the same BuildingWorld schema/history and compensates authored anchors for changed local origins. Manual windows retain tangential world position/height and follow their supporting wall along its normal. Suppressions and unsupported attachments remain recoverable. Preview does not mutate authority; one undo restores bounds and anchors together. Precision horizontal steps are 0.25 world units (paired visible cells), height steps 0.125; normal steps double. Do not claim single-cell horizontal resizing.

## Accepted APK and signing distinction

Keep `hearthvale-m1-repair-44ebca5b.apk` as the accepted player build: 37,786,187 bytes; SHA256 `8472759dde89381e8c8963c4f07a6dad188608d043af3bb43d1deb34770ccef1`.

Private Drive APK: https://drive.google.com/file/d/1HbQ1Vd5vuMEBM_m_zXOFcT72cpPhVBbm/view

Private Drive checklist: https://drive.google.com/file/d/1akgcXywA6CEbsUi2sNsqKtO-ojLr_0ju/view

Its complete successful gameplay/render/APK run is https://github.com/palinalif/Hearthvale/actions/runs/34237601560. APK artifact `10060771655`, source/diagnostics artifact `10060652880`. Existing 11 M1 integration suites and nine additional feature gates passed; the house-action gate has 49 checks and Mobile/D3D12 render coverage has 91, including exact two-cottage colour-cancel and whole-house-move-cancel image restoration. See the preceding handoff at 8f6365c for full historical counts, artifact receipts and the corrected JSON numeric-metadata test comparisons.

The extracted accepted APK size/hash/commit matched the CI receipt. Package/version/signature/Mobile metadata/ARM64-only architecture/pinned native voxel library and development-resource exclusion passed. Prior Drive metadata readback confirmed expected name/MIME/size and shared=false; no remote Drive checksum was supplied or claimed.

The accepted build installs as `Hearthvale Test 44ebca5b`, package `org.hearthvale.game.repair.c44ebca5b`, version code 6 / `0.1.3-repair-44ebca5b`. Existing apps/saves are not replaced or migrated. Never uninstall or clear them to bypass signing. Commit-derived isolated test packages and ephemeral CI keys remain a temporary delivery mechanism, not permanent signing continuity. No private keys were published. Merging into master does not require reinstalling the accepted APK.

## Remaining work, in order

1. Graphical UI polish: proper tool icons, cohesive HUD/panels, typography, controller glyphs and clear focus states. Preserve the accepted controller grammar, cottage-cycling/camera discoverability, single-screen operation and uncluttered miniature presentation. Start from a new branch off master.
2. One-block overhang targeting and Slope performance/plane-guide clarity remain separate open issues; the camera, resize and house-action acceptance did not resolve them.
3. Review the MagicaVoxel tree pilot and choose whether it should replace or extend the procedural tree set. If accepted, add greedy face merging before runtime integration and author the remaining variations through the same staged/provenance-checked path. The current branch also implements the player-approved cottage-only `0.0625` presentation grid for visible roof tiles/edges, window/door joinery, entrance canopy, shutters, trims, flower boxes and flowers, with deterministic craft variations and new headless/actual-Mobile gates. Cottage structure, authoritative roof profile and attachment anchors remain at `0.125`; window/door dimensions use bounded native detail increments. Older saves gain one default editable door without altering other authored edits. See `reports/M1-cottage-half-cell-detail.md`. Player visual approval and Thor performance remain open. No M2, villagers or expanded building catalogue in this pass.
4. Stable securely retained Android signing and deliberate save migration before routine in-place updates.

Pinned Godot 4.7.2.stable.official.ed1daf0bf, locked templates/native Voxel Tools, `0.125` structural visible grid plus the approved cottage-only `0.0625` decorative tier, miniature scale, world dimensions and schemas remain unchanged. Preserve native caves/overhangs, authoritative IDs/manual/suppressed/unsupported records, transactions/cancellation, player saves and old artifacts. Never weaken validation to produce a green result. Local headless and actual-Mobile-render checks passed for the pilot, but neither is a handheld performance measurement or independent review.
