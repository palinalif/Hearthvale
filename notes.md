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

## Status: unit 2 — before/after render evidence + pre-push gate + PR (resume run)
- what changed (no source edits in this unit; evidence + gate + delivery only):
  - `captures/before/*` — master wall appearance: the same
    `tests/cottage_detail_render_test.gd` recipe rendered with master's
    `cottage_visual.gd` injected through the test's own `--baseline-visual=` hook.
    `captures/cottage_visual_baseline.gd` is `git show master:scripts/cottage_visual.gd`
    with the `class_name CottageVisual` line stripped (same 676 lines otherwise),
    so the script swap loads without a duplicate class name.
  - `captures/after/*` — identical camera/recipe with this branch's tone layer.
  - `captures/compare/*` — per-view before|after side-by-side composites.
  - `captures/gate_quick.log` (this run) and `captures/gate_prior_0241.log`
    (an earlier run's legs, kept for comparison).
  - `captures/pr.txt` — PR URL (written at the end of this unit).
- evidence numbers (1280x720, same camera; pixels with any channel |diff| > 8):
  01-normal-clean 3.02 %, 02-close-clean 17.67 %, 03-detail-families 6.80 %,
  04-repeat-stability 6.80 %, 05-resized-details 5.50 %,
  06-editable-openings 11.62 %.
- tests (real output; `GODOT=/opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64`):
  - `tests/house_wall_detail_test.gd` headless → `checks=25 failures=0` exit 0
  - same test, `DISPLAY=:99` + `--renderer mobile` → `checks=28 failures=0` exit 0
    (riverside_cottage: 5 tone batches, 592 bricks, child_count=63;
    village_gable: 3 mottle batches, 70 patches)
  - `tests/building_world_test.gd` headless → `failures=0` `ok:true` exit 0
  - `tests/cottage_detail_render_test.gd` Xvfb + Mobile → `checks=33 failures=0`
    exit 0 (4 runs: standalone, the quick gate, and 2 repeats)
  - the SAME test with master's wall code (`--baseline-visual=`) →
    exit 1 `checks=33 failures=1` "FAIL: unchanged recipe renders identically"
    (2 runs) — i.e. the sibling-recorded pre-existing failure reproduces in this
    sandbox without this branch's layer and does not reproduce with it.
  - `tests/m2_hamlet_composition_render_test.gd` Xvfb + Mobile → PRE-EXISTING:
    `SCRIPT ERROR: Invalid access to property or key 'points'` at line 53, no
    checks line, and the SceneTree never quits (process killed at 200 s).
- quick gate (`bash tools/run_render_gate.sh --quick`), this run's legs:
  - `m1_terrain_navigation_test exit=0 | checks=21 failures=0`
  - `scene_boot_gate_test exit=1 | (no checks line)` — pre-existing: the test does
    not exist on master although the local helper references it
  - `cottage_detail_render_test exit=0 | checks=33 failures=0`
  - hamlet leg never returns → the helper's `QUICK GATE DONE` line is unreachable
    because of that pre-existing non-terminating test. No test file and no helper
    was edited to work around it.
- next: push `task/house-wall-details`, open the PR via REST, GET-verify 200.

## Status: unit 0 — branch created (crash-resume artifact)
- what changed: branch `task/house-wall-details` created off `master` (6ae02f9);
  notes.md stub added. No source edits yet.
- tests: none run yet