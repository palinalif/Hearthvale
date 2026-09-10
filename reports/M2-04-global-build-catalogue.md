# M2-04 — Global build catalogue

Implemented on `feat/m2-hamlet-building` on 2026-09-09.

## Player route

- D-pad Up opens the Build Catalogue from ordinary Terrain or Building play; no existing home selection is required.
- Buildings opens the existing three-home residential catalogue and B returns to the category hub.
- Outdoor Decorations exposes Foliage, Tree, and Clear Decorations brushes and returns directly to Terrain with the chosen brush active.
- Roads & Paths has a visible category slot labelled as the next M2 composition tool. It does not claim or perform road placement before that system exists.
- Tab mirrors D-pad Up in the Windows playtest. Menus retain controller focus and block world edits.

## Evidence

- `tests/m2_home_catalogue_test.gd`: 38 checks, 0 failures.
- `tools/test-m1-placement.ps1`: passed, including placement, catalogue, PC input, controller, camera, layout, cottage edit, and UI gates.
- `tools/check.ps1`: passed (`check ok`), including save/reload, native terrain, controller, PC input, and acceptance fixtures.
- `tests/m2_placement_rotation_render_test.gd` on Godot 4.7.2 Forward Mobile/D3D12: 495 checks, 0 failures. Reviewed captures include the global category hub, Outdoor Decorations, and residential catalogue.

Desktop Mobile rendering is visual-development evidence, not physical Thor approval or performance evidence.
