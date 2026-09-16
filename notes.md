# notes.md — task/house-wall-details

Durable state file. Read FIRST on resume. Format per entry:
what changed / checks=N failures=M / what is next.

## Status: unit 1 — deterministic wall tone layer implemented and tested
- what changed:
  - `scripts/cottage_visual.gd`: new presentation-only wall tone layer.
    `_arm_tone_layer` / `_tone_index` / `_tone_hash` / `_collect_tone_faces` /
    `_collect_gable_tone_faces` / `_flush_tone_faces` / `_oriented_extents`.
    * riverside_cottage (any non-timber material): 5-tone red-brick/ochre
      coursing, 3x2 fine-cell brick + 1 cell mortar joint, running bond, laid on
      the four wall faces and the gable strips above the eave. The wall surface
      keeps its authored material tone, which reads as the recessed mortar bed at
      every joint.
    * village_gable (Tudor): 3 subtle plaster mottle tones (+-4.5% of the chosen
      wall material) in 16x12 fine-cell patches.
    * woodland_lodge: untouched - it already ships two-tone LogCourses.
    * Determinism: pure integer hash of the wall's own cell grid (course, column)
      + coarse patch bias; no RNG, no records, no new authority.
    * Geometry: whole fine cells only (0.0625); boxes emitted axis-aligned in the
      building frame; facing sits one full cell proud of the wall plane.
  - `tests/house_wall_detail_test.gd` (NEW): structural checks always, geometry
    checks when a real display is up (the headless Dummy renderer keeps no
    MultiMesh instance buffers - verified with captures/readback_probe.gd).
- tests: house_wall_detail_test.gd headless → checks=25 failures=0 exit 0;
  same test under Xvfb + Mobile renderer → checks=28 failures=0 exit 0
  (cottage 592 bricks in 5 batches; village_gable 70 patches in 3 batches).
- next: before/after render captures into captures/, then the full gate
  (cottage_detail_render_test.gd, m2_hamlet_composition_render_test.gd,
  building_world_test.gd, tools/run_render_gate.sh --quick), then push + PR.

## Status: unit 0 — branch created (crash-resume artifact)
- what changed: branch `task/house-wall-details` created off `master` (6ae02f9);
  notes.md stub added. No source edits yet.
- tests: none run yet