# notes — task/living-grass (living grass: automatic tufts + per-voxel tone variation)

Resume artifact. Read this FIRST. Format per unit: what changed / checks=N failures=M / next.

## U0 — branch + stub (b2c3c96)
- changed: branch `task/living-grass` created and pushed before any edit (push via GIT_ASKPASS, token never echoed).
- tests: none run (baseline untouched).
- next: baseline recon.

## Baseline facts (before edits, master 6ae02f9)
- quick gate (`bash tools/run_render_gate.sh --quick`; the script is untracked/injected in the sandbox, copied from the sibling sandbox, same md5):
  - m1_terrain_navigation_test exit=0 checks=21 failures=0
  - scene_boot_gate_test exit=1 — **tests/scene_boot_gate_test.gd does not exist on master** (the gate script references it)
  - cottage_detail_render_test exit=1 checks=33 failures=1 — PRE-EXISTING: "FAIL: unchanged recipe renders identically" (repeat-stability pixel check)
  - m2_hamlet_composition_render_test — PRE-EXISTING breakage: "SCRIPT ERROR: Invalid access to property or key 'points' on a base object of type 'Dictionary'" (test still builds `path.points`; painted paths no longer carry points). No checks line.
- Terrain: `scenes/m1.tscn` script = `scripts/m2_scene_starter_valley.gd` (chain head). Grass columns: top voxel type 2, filler type 1, native 0.125 cells, VoxelTerrain + VoxelMesherBlocky library from `M1PatchGenerator.build_library()`.

## U1 — part 1: per-cell grass tone variation (this unit)
- changed:
  - NEW `scripts/grass_tone.gd` (GrassTone): deterministic coherent tone model. 5 ordered meadow greens (deep shade .. light accent), coherent value-noise patch scales 6.0/1.5/0.5 m (weights .45/.35/.20), bounded per-decorative-cell (0.0625 m) jitter FINE_AMPLITUDE 0.30, green-family guard, `digest()` for determinism, `shader_uniforms()` publishing palette + scales (single source of truth).
  - `scripts/terrain_grass.gdshader`: palette/scales/amplitudes now uniforms fed from GrassTone; coherent multi-octave field evaluated per vertex into a varying, interpolated across each voxel face, plus one bounded fragment-level 0.0625-cell jitter; keeps edge/side shading and the mesher's COLOR multiply. No texture, no tiling, no terrain authority change.
  - `scripts/m1_patch_generator.gd`: new `grass_material()` helper (testable) sets every GrassTone parameter on the grass ShaderMaterial; `build_library()` uses it. No generation/voxel change.
  - NEW `tests/grass_tone_test.gd`.
- checks: `grass_tone_test checks=28 failures=0` (exit 0). Key lines: albedo digest stable across two evaluations and after patch regeneration (`9fc464a7a1847cdb`), 5/5 tones reachable, 0 samples outside the green family, neighbour tone delta 0.205 vs 0.614 for distant cells (coherent patches, not noise), all 12 published uniforms declared by the shader and applied to the material, regenerated native patch byte-identical (`patch_digest 0ea4e7ccbbc17c73`).
- smoke: one render-session run reached the scene + terrain (no SHADER ERROR in log) but the run died in the test's own pre-existing `path.points` bug, so shader compile is NOT yet verified by a full render gate.
- next: part 2 (automatic tufts), tuft tests, captures, gate, PR.

## Pickup by Pi (2026-09-17): rebased onto main, re-PR'd
- context: PRs #21/#22/#23 were found closed unmerged (not intentional) and their
  base branch `master` had been deleted, so GitHub cannot reopen them. Notes moved
  from root `notes.md` to this file to end the permanent conflict.
- changed: rebased onto `main` (f610176). No feature-code changes.
- tests (local headless, stock Godot — no native voxel module): grass_tone_test
  26 checks / 1 fail "native VoxelBuffer unavailable" (environmental; same
  limitation on plain main).
- delivery: forced push; new PR https://github.com/palinalif/Hearthvale/pull/25 (base main).
- next: CI green on #25, then part 2 (auto-scattered tufts) on this branch.

## U2 — part 2: auto-scattered meadow tufts (cffc881)
- changed:
  - NEW `scripts/grass_tuft_scatter.gd` (GrassTuftScatter): pure-logic deterministic
    planner. Coarse 0.25 m candidate lattice hash-preselected (never scans the ~1M
    fine grid), tone-field clump bias (lifted patches carry more tufts), exclusion
    rects (paths/water/stone/foundations), fine-cell occupancy, 1-2 cell ground-cover
    columns with optional companion, hard MAX_TUFTS cap. Integer identity only —
    no RNG/frame time/terrain revision/enumeration order. `digest()` for determinism.
  - `scripts/m1_garden_visual.gd`: builds ONE batched tuft ArrayMesh (vertex-coloured
    per tuft tone) on attach + refresh_terrain, native-validated per column (grass
    type 2, above-surface, companion within 2 fine cells), deduped on (revision,
    exclusions digest). Excludes hand-planted records + building foundations.
    Presentation only: no planting records, no terrain writes, no save data.
  - `scripts/m1_scene.gd`: `_sync_meadow_exclusions()` pushes building-foundation
    rects on terrain/building change. `scripts/terrain_backend.gd`: trivial
    `revision()` getter for the dedupe key.
  - NEW `tests/grass_tuft_scatter_test.gd`, `tests/meadow_tuft_visual_test.gd`.
- checks (local headless, stock Godot, no native voxel module):
  - grass_tuft_scatter_test 16/0 (225 tufts, sparse 0.055/m^2, clumping 1.25x lifted,
    exclusions respected, unique cells, ground-cover bounded, green family).
  - meadow_tuft_visual_test 11/0 (mock flat-grass backend: 390 cells/9360 verts,
    deterministic rebuild 9360==9360, no-op refresh no-rebuild, exclusion 9360->8496->9360,
    stone surface -> 0 tufts, sits-on-grass no-sink).
  - grass_tone_test 26/1 (1 environmental "native VoxelBuffer unavailable", same on main).
  - import check clean.
- native legs (real terrain surface/grass detection, live building+record exclusions,
  in-scene render) are CI-gated; not verifiable in this sandbox (no native module).
- next: CI green on #25; then merge (after #24 wall-details, before #26 landing).
