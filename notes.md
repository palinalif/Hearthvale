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
