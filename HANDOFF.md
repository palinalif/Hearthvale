# Hearthvale — current M2 handoff

Updated 2026-09-09 during M2-02 on `feat/m2-hamlet-building`. Read AGENTS.md, `tasks/M2-hamlet-building.md`, and the latest user request first. **M1 is complete and M2 is active.** M2-01 provides controller-first translation/rotation, explicit bounds/overlap validity, atomic confirmation, cancellation, undo/redo and save compatibility. M2-02 adds a real controller residential catalogue and three independent saved recipes: the retained riverside cottage, a broad low timber lodge, and a narrow tall village gable. Shape, style, roof profile, wall material and roof material are authoritative; catalogue browsing/choice is preview-only until confirmation, and fresh homes receive independent building/surface/detail IDs. See `tasks/M2-02-residential-catalogue.md` and `reports/M2-02-residential-catalogue.md`. Physical Thor feel and player visual approval remain separate. Verified Drive delivery triggers on every branch push (but not tags), cancelling an older in-progress delivery for the same branch so only its newest commit can upload. The Thor-accepted M1 interaction baseline remains `44ebca5b`; the final M1 visual/performance/device receipt is `reports/M1-e3ef8e0d-thor-acceptance.md`.

M2-03 expands that catalogue into distinct cottage/lodge/Tudor window and door families, opening-aware log and Tudor wall treatments, and manual placement of additional structural openings. Window and door variations are categorized. Colour/variation pickers dock away from their target and use live preview; amber highlighting now follows actual detail geometry and whole-house geometry in terrain targeting instead of projected rectangles. See `tasks/M2-03-home-details-ui.md` and `reports/M2-03-home-details-ui.md`.

M2-04 promotes placement into a global Build Catalogue opened by D-pad Up (Tab on PC), without selecting an existing home or changing edit context first. Its category hub routes Buildings to the residential catalogue and Outdoor Decorations to the existing foliage/tree/clear brushes; Roads & Paths is visibly reserved for the next composition slice and does not pretend placement exists. See `reports/M2-04-global-build-catalogue.md`.

M2-05 expands every editable building-decoration family before road work: windows now have 7 choices, doors 6, shutters 4, and flower boxes 4. Shutters and planters now expose the same dock-away live Variation browser as structural openings; legacy asset IDs keep their prior deterministic appearance, while new IDs select stable adaptive geometry on the 0.0625 detail tier. Preview/cancel, one-edit commit, undo/redo, and exact save/reload identity are covered. Tested source `2b3b4ea5` passed delivery run `34394758607`, including the 1280×720 D3D12 Forward Mobile capture, verified ARM64 APK and Windows ZIP, and private Drive upload. See `tasks/M2-05-building-decoration-variants.md`, `reports/M2-05-building-decoration-variants.md`, and `reports/screenshots/m2-home-details/decoration-variants.png`. Physical Thor/player approval remains open.

M2-06 implements the first Roads & Paths vertical slice. The global category now opens a three-style path catalogue (packed earth, cobblestone, and stepping stones), followed by a controller-first polyline preview with add/remove/finish/cancel, orbit, zoom, explicit validity reasons, home-intersection checks, stale-result rejection, and focus/disconnect safety. Paths are optional save data with stable IDs and snapped points; geometry is presentation-only and never edits native terrain. A confirmed path plus nearby planting clear is one landscape history transaction, while cancel restores the exact document. `tests/m2_path_state_test.gd` passes 18 checks, `tests/m2_path_placement_test.gd` passes 30, and the actual Forward Mobile/D3D12 render passes 16 with `reports/screenshots/m2-paths/all-styles.png`. `tools/test-m1-placement.ps1` and `tools/check.ps1` pass. Source `822ffaa` passed verified delivery run `34404866082`, including the verified ARM64 APK, Windows x86-64 ZIP, and private Drive upload. See `tasks/M2-06-roads-and-paths.md` and `reports/M2-06-roads-and-paths.md`. This desktop evidence is not physical Thor or player approval.

Every branch push now exports both the isolated ARM64 APK and the Windows x86-64 playtest ZIP. CI launches the Windows export headlessly, verifies the exact ZIP contents/PE architecture/PCK/instructions, versions both packages by commit, and uploads them as separate GitHub artifacts. Only after the full gameplay/render/package gates pass does the existing private Apps Script bridge copy both artifacts and their verification receipts to Google Drive. See `reports/M2-PC-Drive-delivery.md`.

## Current visual-finish branch

On 2026-09-09 the player approved the half-size foliage and requested the earlier
mushroom coloring plus placement variety. Mushroom sources restore the exact
7131d22 pale-stem/warm-cap palette. Foliage and rocks receive subtle deterministic
per-instance hue/value modulation without extra draw batches. Tree rotations are
derived deterministically from existing planting records using the home's
15-degree coarse steps; foliage retains cardinal quarter turns. This covers the
starter scene and both brushes without changing saves, anchors, voxel cells,
undo/redo, or rock orientation.

On 2026-09-09 the player approved the 0.0625 detail cells but clarified that all
eleven ground-foliage variants should also be physically smaller. Their authored
sources are now half the 7131d22 linear dimensions, with trees and rocks unchanged.
All three mushroom variants retain broad cap geometry above narrow stems, with
every cluster grounded. Placement anchors, brush indices, and saves
are unchanged. See `foliage-halfsize.authoring.json`.

On 2026-09-09 the player clarified that the authored trees were correctly sized
overall but their 0.125 cells made vegetation feel too blocky, then explicitly
included rocks in the finer tier. All six gameplay trees, eleven foliage assets,
and three authored rocks were MCP-resampled to solid 2x2x2 sources at 0.0625 and
given 2,487 grounded-safe half-cell silhouette cuts. World-space bounds and saved
placement remain unchanged. The rock batches now use the authored slab/split/moss
resources instead of procedural geometry. Mushroom tests require the warm cap
surfaces to remain above the cream stems. See `fine-prop-grid.authoring.json` and
`reports/screenshots/fine-prop-grid.png`. Desktop Mobile review passes; CI/APK and
physical Thor approval must be recorded before calling this delivered.

The graphical UI, cottage-detail scale/variation, editable window and door, and in-world resize-handle passes are implemented on `feat/m1-ui-polish`. The latest environment pass replaces the straight presentation channel with a native-grid winding river and graded banks, changes the default scatter into deterministic planting drifts with deliberate cottage clearings, and gives the three tree variants broad orchard, tall riverside, and asymmetric wind-shaped silhouettes. It does not add a new catalogue or a water-editing system.

Fresh terrain uses the new river contour. Water is rebuilt from authoritative terrain cells after generation/load, so existing v2 saves keep water aligned to their original straight channel and are not rewritten by the new generator presentation. The focused riverbank gate checks a 2.25-unit centreline span, varying width, dry banks, the unchanged cottage pad, native-grid water geometry, upward winding, and old-save channel reconstruction. `tools/check.ps1` passes with this gate included; the actual Mobile vegetation/grid run passes 322,678 checks. Deterministic before/after captures are in `reports/screenshots/m1-riverbank-before.png` and `reports/screenshots/m1-riverbank-after.png`. Player visual approval and Thor performance remain open.

MagicaVoxel MCP is now available as a pinned, staging-only asset-authoring path. Codex registration is named `hearthvale-magicavoxel`; it launches commit `710671d49bdc89e4e3d1ff7c60541c1d0383ac16` through a private wrapper that rejects paths and confines all MCP writes to ignored `.tools/magicavoxel` folders. The upstream server requires `mcp==1.0.0`; its unconstrained requirements currently install an incompatible MCP 2.x API, so preserve the pinned environment/receipt under `C:\Users\Pali\.codex\mcp`. A new Codex task is required to discover the newly registered server.

The first protocol-level pilot called the real server, discovered 40 tools, generated six snapshots, and produced the project-authored `hearthvale_tree_pilot_broad.vox`. The reviewed source is copied to `assets/source/magicavoxel`; `vox_to_obj.py` removes internal faces and emits provenance, then `bake_mesh.gd` restores the exact 0.125 grid after Godot import. The candidate preserves four authored palette groups, contains 7,611 voxels / 6,968 triangles, and passes 25 headless asset checks plus 27 checks on the actual Mobile renderer. It is intentionally not wired into gameplay yet. The comparison capture is `reports/screenshots/magicavoxel-tree-pilot.png` (current tree left, MCP candidate right); player preference should decide whether to iterate, optimize, and integrate it.

The Drive delivery workflow matches the deployed Apps Script contract: repository secrets `APPS_SCRIPT_WEBHOOK_URL` and `APPS_SCRIPT_WEBHOOK_SECRET`, plus the `GOOGLE_DRIVE_UPLOAD_ENABLED` switch. After every prerequisite gate and both package verifications succeed, CI resolves each authenticated GitHub artifact endpoint to a short-lived signed URL and sends only that URL and the webhook secret to Apps Script. The receiver downloads the separate archives and admits the versioned APK, Windows ZIP, and JSON receipts privately. Automatic delivery runs on every branch push and can also be started manually. The Apps Script receiver checks its 50 MiB per-artifact archive ceiling before downloading.

## Three MagicaVoxel tree review candidates (2026-09-08)

The `d2535ed` MCP pipeline baseline now has three review-only alternatives:
`hearthvale_tree_orchard`, `hearthvale_tree_riverside`, and `hearthvale_tree_wind`.
The user rejected the first chunky shelf-shaped crowns and requested a trunk
repair; the final MCP-authored sources use 22/16/20 small overlapping sprays,
tapered bent trunks, thin forks and small roots. Six six-angle snapshot passes
per candidate remain in ignored staging, along with rejected models. Canonical
VOX sources, exact MCP operation records, converted OBJ/MTL receipts and baked
RES meshes are retained. Existing procedural/gameplay trees and pilot assets
are unchanged. No integration is approved.

Final triangle counts are 2,274 / 1,548 / 1,918. The opt-in converter now merges
same-palette coplanar faces with exact unit-face coverage regression. Baking
enforces matte foliage/bark after actual Mobile captures exposed the OBJ
importer's metallic=0.999 interpretation. All candidates pass 121 headless
asset checks and 125 checks per actual Mobile capture run (front/close,
normal-distance and reverse). The full suite result and reproduction commands
are recorded in `reports/MagicaVoxel-tree-candidates.md`.

The user liked the revised set and requested a small tree #1 top-variation pass.
That pass lowers matching caps, adds broad low shoulders and one taller offset
tip, with a seventh orchard MCP snapshot and separate provenance operation log.
It passes 121 headless checks, mesher coverage and 125 checks per fresh Mobile
close/normal/reverse run. The earlier full-suite pass is reused for this
source-only tweak. Gameplay integration remains unperformed.

Review `reports/screenshots/tree-candidates-comparison.png` (current left,
candidate right in each labelled row). Player judgement of foliage rhythm and
thin trunk proportions, plus Thor performance, remain open. Ask which
candidates, if any, the user wants integrated; do not replace gameplay trees
based on automated validation alone.

## Gentle wind study

The user explicitly approved trying render-only off-grid tree sway. The new
standalone `scenes/tree_wind_preview.tscn` uses the three approved candidate
meshes with a subtle 12-second shader cycle, individual phases, fixed ground
contacts, corrected normals and expanded culling bounds. Space pauses; W
toggles wind. Affine height-weighted motion preserves the greedy mesh's shared
edges without subdivision. The authored 0.125 rest grid and gameplay remain
unchanged. This animation exception does not apply to simulation or placement.

See `reports/Tree-wind-preview.md` and the actual Mobile loop at
`reports/screenshots/tree-wind-preview.mp4` / `.gif`. Headless wind checks and
actual Mobile reference-render/pause checks pass; the normal suite now includes
the wind gate. The player approved the tree motion and requested the remaining
ground foliage receive the same treatment. Physical Thor performance remains
open. No automatic gameplay integration was performed.

## Ground foliage and wind review (2026-09-08)

Three new MCP-authored sources `hearthvale_foliage_grass`,
`hearthvale_foliage_wildflowers`, and `hearthvale_foliage_leafy` are promoted
through the existing pipeline with receipts and palette groups: 206 / 226 / 232
triangles. Source rest geometry remains 0.125. The user-authorized render-only
wind exception also covers this ground foliage trial. The standalone
`scenes/foliage_wind_preview.tscn` compares old/new; `-- --context` adds approved
trees at true scale. Grass/flowers/leaves use smaller wind strengths and
independent phases. Gameplay and cottage flower boxes are untouched.

See `reports/Foliage-candidates.md`, its labelled comparison and the two
`reports/screenshots/foliage-wind-*.mp4` loops. Asset checks (54), headless wind
checks (21), and actual Mobile close/context checks (30 each) pass. Palette,
pivot, bounds, budget, rest grid, rooted components and exact exposed-cell
coverage are verified. Player review and Thor performance remain open.
The final normal `tools/check.ps1` suite passed; see
`reports/logs/foliage-check-suite-rerun.log`. An initial terrain acceptance failure
passed both its isolated retry and the full rerun without code changes; the report
retains this transient failure rather than discarding its evidence.

## Additional meadow review candidates

The user liked the first foliage set and requested three further flower/grass
variants plus rocks. Six new MCP-authored review sources are retained:
`foliage_seedgrass`, `foliage_cream`, `foliage_mauve`, `rock_slab`, `rock_split`,
`rock_moss` (each prefixed `hearthvale_`). Triangles: 168/212/208 and 120/154/142.
Plants reuse gentle render-only sway; rocks stay static. Rest geometry is 0.125.
All have provenance receipts/palette groups through VOX → greedy OBJ → baked RES.
No gameplay replacement or cottage-flower change is included. Review
`reports/Meadow-expansion-candidates.md` and `scenes/meadow_expansion_preview.tscn`.
The new headless asset gate has 117 checks; all 12 candidate sources now receive
bounded Python exact-coverage/root-connectivity validation in the normal suite.
Close and tree-scale actual Mobile runs each pass 44 checks. The full suite
attempt stopped at import on undeclared `kind`/`variant` in the independently
modified `scripts/m1_garden_visual.gd:38–42`; this pass left that work untouched.
See `reports/logs/meadow-expansion-check-suite.log`. The earlier foliage full-suite
pass does not establish a pass for this later shared-workspace state.
After the independent parse fix, the rerun reached `visual-grid` but failed on
the concurrent gameplay wind integration calling `set_surface_override_material`
on `MultiMeshInstance3D` through `M1GardenVisual`. Preserve
`reports/logs/meadow-expansion-shared-wind-failure.log`; that integration was left
untouched. Standalone MeshInstance3D previews pass 35 headless / 44 Mobile checks.

## Woodland and riverside review additions

The user approved making reeds, fern and mushrooms. These are new standalone
MCP-authored sources `hearthvale_foliage_reeds`, `hearthvale_foliage_fern`, and
`hearthvale_foliage_mushrooms`, with receipts/palette groups and 212/274/182
triangles. Rest geometry remains 0.125. Reeds/fern sway gently; mushrooms stay
static. This pass does not wire these three into gameplay. See
`reports/Woodland-candidates.md` and `scenes/woodland_preview.tscn` (optional
`-- --context` for tree scale). Asset checks pass 54, and close/context actual
Mobile checks pass 29 each. Meshing validation includes all 15 source candidates.
The shared wind test now handles two or three animated instances and separately
checks static mushroom materials/transforms. Independent review found no defect.
The full normal suite now passes (exit 0 / `check ok`), including 20 headless
woodland wind checks; see `reports/logs/woodland-check-suite.log`. The prior
shared-workspace integration errors did not recur. Physical Thor performance
and player visual approval of this set remain open.

## Compact trees and flat mushroom review additions

At the player's request, the three approved trees now have new MCP-authored
roughly-80% companions: `tree_orchard_compact`, `tree_riverside_young`, and
`tree_wind_low` (prefix each with `hearthvale_`). Two static low mushroom patches
were also added: `foliage_mushrooms_flat` and `_flat_scatter`. Triangles are
1,696/1,128/1,448 and 178/222. Compact trees retain gentle sway; mushrooms stay
static. The first MCP resample produced odd horizontal volume sizes, causing
half-cell centering and collapsed bake faces; those blockouts were rejected and
MCP-unioned into even horizontal declared volumes. Final rest geometry is cubic
on 0.125, grounded, palette-preserving and provenance checked. Originals remain
byte-identical and have pinned baked bounds. No gameplay integration was done.
See `reports/Size-variation-candidates.md` and
`scenes/size_variations_preview.tscn`. Targeted asset/Mobile checks pass 104/40;
the converter now validates all 20 candidate sources. Independent review found
no defect and its requested original-immutability assertions were added.
The final normal `tools/check.ps1` suite passes with exit 0 / `check ok`; see
`reports/logs/size-variations-check-suite.log`. Actual Mobile has 40 passing
checks and the normal suite's headless size-variation wind gate has 31.

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
