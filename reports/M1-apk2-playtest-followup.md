# APK 2 Thor playtest follow-up — 2026-09-08

Baseline: `4b0e864cad510090e5384e59e70a763c7510d857`, the shipped `m1-ui-ux` APK. The user supplied an actual Thor playtest. Earlier green CI did not establish usability or complete visual correctness. **Cottage editing and the full UI pass are reopened. No higher-detail cottage work until these blockers are resolved.**

The separate APK 1 terrain follow-up is NOT merged here. `master` and the shared APKs are unchanged by this workstream.

## Reported passes to preserve

D-pad Up context switching and mode indication; selected-building orbit, tilt and zoom; camera stability during detail edits; attachment ghost creation, deliberate wall switching, confirm/cancel and basic corner constraints; basic resizing; attachment survival in the tested resize; duplicate ghost/free placement/precision/confirm/cancel; no observed mutation of the original when editing its duplicate.

## Priority 1 — reliable targeting and feedback

- The shipped picker tests local -Z as an outward wall normal even though the renderer extrudes detail geometry in local +Z. That reverses front/back rejection. Correct this and independently test known front/back/left/right geometry, rotation and two cottages.
- Replace the font-dependent full-width-plus pointer with geometry. The reported hexadecimal box is consistent with missing-glyph rendering, not a usable reticle.
- Hide the terrain reticle in building editing; keep one relevant pointer.
- Highlight the exact target and attach `A Move / X Options` above it. Replace the broad centre-distance magnet with a bounded projected footprint and modest padding.
- Reject stale detail IDs from another selected building. Inspect apparent cross-cottage picking separately from actual authoritative mutations.

The first code patch addresses the items above. CI and device acceptance must be reported separately; no physical Thor validation has been performed for the patch.

## Priority 2 — explicit entry, back navigation and cameras (pending)

Requested: while in Terrain, hover a cottage to highlight it and show `X Edit cottage`; X selects THAT cottage and enters editing. A remains the terrain action. In Building, only the selected cottage's details are editable. B cancels an active operation/closes its menu first, and exits cottage editing when idle. D-pad Up remains the global context shortcut.

The return-to-old-terrain-view jump was intentional under the earlier design. Revise the transition so leaving editing does not abruptly move the view. Keep full orbit while editing and preserve current viewing direction/framing where practical. Duplication explicitly uses the free terrain-like camera, then restores cottage orbit after cancel/place. Building switching must be discoverable, not an undocumented D-pad dependency.

## Priority 3 — rendering and style isolation (pending)

Investigate massive Z-fighting during recolouring. Confirmed code hazard: `_selected_visual_roots()` includes the first cottage renderer AND the selected renderer; `_apply_style_preview()` rebuilds BOTH with the selected cottage recipe. With B selected, that can render two copies of B at the same transform. Test rendered building IDs/transforms throughout preview, cancellation, commit, selection changes and undo, not just document revisions. Also check per-cottage colour persistence and single-cottage material geometry.

## Priority 4 — wall attachment placement and recovery (pending)

Start on the visible/hovered camera-facing wall, not a previous stale support or first wall. Keep explicit wall switching. Investigate vertical sticking: alignment currently overwrites the movement position each frame, which can trap small repeated stick deltas inside a snap band. Preserve a separate unsnapped movement accumulator with a clear precision/snap escape. Keep wall bounds and collision feedback distinct from snapping.

Make Needs Placement controller reachable and focusable. Selecting an item must recover that item into a wall-locked ghost, with A place/B restore. The reported unrecoverable shutter remains a blocker.

## Priority 5 — resize interaction and layout (pending)

Replace automatic shell-body resizing with visible selectable side/corner/height handles. Drag a side to expand that side; corners affect both adjacent axes. Test wide/narrow/tall/short, all viewing sides and manual-window stability. Window proportions and automatic layout were only partially accepted; do not mark them complete. Preserve attachment identities and recoverability.

## Required next acceptance

Run existing M1 tests plus exported-scene regressions with independently specified wall orientations, two visibly distinct cottages, real input routing and rendered state assertions. Obtain Mobile-renderer captures of hover, style preview/cancel, resize and recovery; then produce one clearly versioned combined APK and a focused checklist. Automated correctness, desktop rendering and Thor usability are distinct results. Do not call the overhaul done based on label-existence tests.
