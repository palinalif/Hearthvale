# M2-02 residential catalogue

Implemented on `feat/m2-hamlet-building` on 2026-09-09.

## Delivered

- A controller-first **Place new home** catalogue with three drawn silhouettes, names, shape/style summaries, and live wall/roof selections.
- D-pad up/down selects a design, left/right changes walls, LB/RB changes the roof, A enters the complete placement ghost, and B returns without mutation.
- Riverside Cottage, Woodland Lodge, and Village Gable use different saved footprints, proportions, roof slopes, architectural accents, and default material pairings.
- Confirmed catalogue homes allocate fresh building, surface, and attachment IDs without cloning the selected cottage.
- Shape, style, roof profile, wall material, and roof material survive save/reload. Existing M1 documents remain valid through fallback fields.
- Existing-home options expose wall and roof material changes separately.

## Local evidence

- `m2_home_catalogue_test`: 24 checks, 0 failures.
- `m2_placement_rotation_test`: 26 checks, 0 failures.
- `building_world_test`: passed.
- `tools/test-m1-placement.ps1`: complete suite passed.
- Actual D3D12 Mobile catalogue/UI render: 408 checks, 0 failures.
- Actual D3D12 Mobile three-home comparison: 5 checks, 0 failures.

Review captures:

- `reports/screenshots/m2-home-catalogue/three-home-recipes.png`
- CI retains `20-m2-home-catalogue.png` with the exact-source diagnostics artifact.

Desktop Mobile rendering is not physical Thor performance evidence or player visual approval.
