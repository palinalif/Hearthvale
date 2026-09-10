# M2-05 — Building decoration variants

**Status:** implemented, verified, and delivered from tested commit `2b3b4ea5`; physical player review remains open.

## Scope

- Give every player-placeable building decoration family an intentional geometry browser: windows, doors, shutters, and flower boxes.
- Retain the existing styles and add cottage, lodge, and Tudor alternatives without reducing any home to palette swaps.
- Expose the previously derived shutter and planter craft differences as explicit player choices.
- Use the existing live-preview, dock-away, controller focus, colour, cancellation, undo/redo, resize, recovery, and save contracts.
- Keep decorative geometry on cubic `0.0625` presentation cells while structural openings, anchors, collision, and authoritative sizes remain on `0.125`.

## Acceptance

- Every placeable detail kind has at least three selectable geometric variations.
- Browsing changes the visible selected mesh immediately; B restores the exact original and A records one authoritative edit.
- Choice labels and categories are readable at 1280×720 and work with controller and mouse.
- Variant IDs survive resize, recovery, duplication, save/reload, undo, and redo.
- Actual Mobile captures visibly distinguish representative options from all four families without the picker covering its target.

## Delivered set

- Windows: 7 options across cottage, lodge, and Tudor joinery.
- Doors: 6 options across cottage, lodge, and Tudor joinery.
- Shutters: legacy hand-built mix plus boarded, louvered, and diagonal-braced crafts.
- Flower boxes: legacy garden mix plus timber, bracketed, and woven crafts.

## Evidence

- `tests/cottage_detail_visual_test.gd`: 264 checks, including explicit craft IDs, distinct geometry, and the `0.0625` detail grid.
- `tests/m1_cottage_edit_ux_test.gd`: picker availability, read-only preview, commit, undo/redo, and exact save/reload identity.
- `tests/m2_decoration_variants_render_test.gd`: 11 checks on D3D12 Forward Mobile at 1280×720.
- `reports/screenshots/m2-home-details/decoration-variants.png`: actual Mobile gameplay capture.
- `tools/test-m1-placement.ps1` and `tools/check.ps1`: exit 0.
- Delivery run `34394758607`: success; verified ARM64 APK and Windows ZIP copied to private Google Drive.
