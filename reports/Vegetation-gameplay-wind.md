# Gameplay vegetation wind

Implemented 2026-09-09 on `feat/m1-ui-polish` for the approved M1 tree and
ground-foliage families.

## Result

- The starter scene and both planting brushes share `M1GardenVisual`, so every
  existing and newly planted tree/foliage instance receives the same gameplay
  wind path without changing placement records or saves.
- The shader deforms the already-approved `0.0625` rest meshes directly. Roots
  at Y=0 remain fixed; authored cells, physical bounds, pivots and collision are
  unchanged.
- Every planting record receives a stable deterministic phase through
  `MultiMesh` custom data. Palette surfaces for one asset share its phase and
  complete-asset height, preventing seams while neighbouring plants move
  independently.
- Tree crown travel retains the approved `0.16` world-unit maximum. Ground
  foliage keeps the gentler per-family strengths from the review previews.
  Mushrooms and rocks remain static, while foliage and rock tint variation is
  preserved.
- Animation is GPU-only and keeps the existing per-variant/per-palette batching;
  it does not add one node or draw batch per planted instance.

## Evidence

- Gameplay vegetation integration: 686 checks passed, including authored palette
  preservation and seam-synchronized phases across every palette surface.
- Existing headless tree wind: 21 checks passed.
- Existing headless foliage wind: 21 checks passed.
- Visual-grid regression: 1,196 checks passed.
- Landscape write/cold-read: 123 + 6 checks passed, including the real starter,
  tree-brush and foliage-brush paths.
- Actual Forward Mobile render: 5 checks passed, including retained independent
  phases, palette-surface synchronization and a frame-difference assertion
  proving that gameplay-batched vegetation moves over time.
- Normal `tools/check.ps1`: passed.

Actual Mobile review capture:
`reports/screenshots/vegetation-wind-gameplay.png`.

Desktop Forward Mobile evidence is not physical AYN Thor performance evidence.
