# M1 cottage half-cell detail candidate

This branch implements the player-approved `0.0625` cottage presentation tier, including visible roof tiles and edges, while retaining `VisualGrid.UNIT = 0.125` for terrain, cottage structure, authoritative roof profile, resize increments and attachment anchors.

The derived renderer gives existing windows finer mullion/transom choices, enlarged chamfered round surrounds, slatted or stepped-braced shutters, thinner cornices, regular eave pegs, articulated ridge and roof lips, half-cell visible roof courses, built timber flower boxes, and small deterministic flower arrangements. Building seed plus stable detail identity selects restrained variations. A subsequent accepted-scope edit makes window sizes authored overrides and migrates the entrance from baked shell geometry to a stable movable, resizable and recolourable door record; its cutout and half-cell porch follow it. The schema number remains compatible and older valid cottages receive one default editable door during load.

The editable-opening pass passed the complete `tools/check.ps1` regression, a 33-check deterministic Forward Mobile capture, and an actual Mobile grid run with 322,678 checks across 107,084 instances and 2,637,056 inspected vertices. The dedicated entrance view is `reports/screenshots/m1-cottage-detail/06-editable-openings.png`. These desktop checks establish recipe/render consistency, not Thor comfort or performance.

Validation on pinned Godot `4.7.2.stable.official.ed1daf0bf`:

- Focused headless detail geometry: 227 checks, 0 failures, including the enlarged `0.375 x 0.375` world-unit round pane on a default miniature cottage.
- Full headless visual-grid contract: 1,173 checks, 0 failures. Native MultiMesh instances are explicitly unverified in headless mode.
- Actual D3D12 Forward Mobile grid: 321,029 checks, 0 failures; 106,543 rendered instances and 2,623,712 vertices inspected across the seven-cottage scale/resize/duplication stress fixture.
- Focused Forward Mobile capture harness: 26 checks, 0 failures, including exact repeated-image stability and unchanged authoritative records.
- Existing building-world serialization, duplication, undo/redo and revision guards passed.
- Existing cottage render stability passed 35 checks.
- The full repository `tools/check.ps1` gate passed, including the 112-check cottage acceptance scenario and 8-check cold reload.
- GitHub workflow YAML parsed successfully after adding headless detail and actual Mobile grid/capture gates.

Review captures:

- `reports/screenshots/m1-cottage-detail/01-normal-clean.png`
- `reports/screenshots/m1-cottage-detail/02-close-clean.png`
- `reports/screenshots/m1-cottage-detail/03-detail-families.png`
- `reports/screenshots/m1-cottage-detail/05-resized-details.png`
- Same-view baseline: `reports/screenshots/m1-cottage-detail-baseline/03-detail-families.png`
- Same-view pre-fine-roof baseline: `reports/screenshots/m1-cottage-detail-roof-baseline/03-detail-families.png`

The authoritative roof profile remains structural while its visible courses use the finer tier. Halving both roof tile axes substantially increases generated instances in the multi-cottage diagnostic fixture. Desktop RTX 3070 evidence is not Thor performance evidence; handheld performance and player visual approval remain open.
