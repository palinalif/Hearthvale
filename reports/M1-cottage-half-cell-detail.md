# M1 cottage half-cell detail candidate

This branch implements the player-approved `0.0625` cottage decorative tier while retaining `VisualGrid.UNIT = 0.125` for terrain, cottage structure, roof mass, resize increments and authoritative attachment anchors.

The derived renderer now gives existing windows finer mullion/transom choices, chamfered round surrounds, slatted or stepped-braced shutters, thinner cornices, regular eave pegs, articulated ridge and roof lips, built timber flower boxes, and small deterministic flower arrangements. Building seed plus stable detail identity selects restrained variations; unchanged recipes render identically and no save schema or gameplay behavior changed.

Validation on pinned Godot `4.7.2.stable.official.ed1daf0bf`:

- Focused headless detail geometry: 202 checks, 0 failures.
- Full headless visual-grid contract: 1,173 checks, 0 failures. Native MultiMesh instances are explicitly unverified in headless mode.
- Actual Vulkan Forward Mobile grid: 92,900 checks, 0 failures; 30,507 rendered instances and 798,848 vertices inspected.
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

The large structural roof staircase remains intentionally on the `0.125` tier and still dominates the silhouette. Desktop RTX 3070 evidence is not Thor performance evidence; handheld performance and player visual approval remain open.
