# Hearthvale visual run — step 3 of the visual overhaul (camera clamp + hamlet extension + real DOF)

## What's in the cwd
This is the live working copy at `/opt/data/sandboxes/Hearthvale-visual`
(GitHub: https://github.com/palinalif/Hearthvale, branch `task/visual-overhaul-1`,
current HEAD includes commit `d357e5c v5.3: warm dusk grade...`).

READ THIS FILE FIRST, IT IS THE DURABLE STATE: `notes.md` at repo root.
The last "Hermes continued (2026-09-15...)" section has the full chain map,
measured test evidence, and your task. Do NOT re-explore the repo for the chain —
the map is verified:
- LIVE camera is created at `scripts/m2_scene_upper_wall_details.gd:88` (Camera3D, fov 52, NO attributes).
- LIVE WorldEnvironment (sky/fog/grade) is built in that same file.
- `scripts/m1_scene.gd` is DEAD CODE — it holds DOF helpers that the live game never uses.
- Chain top: `scenes/m1.tscn` -> `scripts/m2_scene_style_preview_stability.gd`.

## Engine + environment (already here — do NOT re-download)
- Godot: `/opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64`
- The voxel/zylann addon is ALREADY extracted into the sandbox (`addons/zylann.voxel/`).
- Xvfb display `:99` is running; render tests use `DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 --renderer mobile`.
- Every godot command MUST use an explicit high timeout (>= 600 s). A bare command gets killed at ~120 s.

## Task (do all four, in this order)
1. **Camera pitch clamp (Pali's explicit ask):** extend the live hamlet camera's pitch/look range in
   `scripts/m2_scene_upper_wall_details.gd` (or wherever the chain clamps it — house_editing 0.08-1.40,
   pc_input 0.08-1.40, roof_accessories 0.15-1.25) so the camera CANNOT tilt up far enough to show
   the sky band. Add/extend the live input clamp; the existing clamps are per-file — find which one
   the live m2 chain hits and tighten the max (look-at angle), keeping min.
2. **Extend the hamlet cluster (content):** the full-hamlet shot (tests/m2_hamlet_composition_render_test.gd
   captures it) currently shows ~2-3 buildings in a "warm void". Scatter 1-2 more distant farm/hill
   masses (low-poly static meshes from assets/models OR simple ColorSurfaceMaterial boxes, no new
   archetypes — Pali's asset list is fixed) positioned beyond the existing cluster so the horizon
   reads "further village + rolling hills in the fog", not "empty warm plane". They must be STATIC
   (no new node types, no new scene files) and must not break the existing 57-check foliage test
   (tests/foliage... — do not touch foliage logic) or the 33-check cottage test.
3. **Wire REAL DOF into the LIVE camera:** create a `CameraAttributesPractical` child on the
   `Camera3D` built in `scripts/m2_scene_upper_wall_details.gd`, with a gentle focus range
   (near blur ~0.6-1.2px at distance, focus_distance ~18-30) + a small blur amount — the m1_scene.gd
   DOF helpers (`_update_depth_of_field`, dof_blur_*) are DEAD CODE, they never ran live. The proof
   capture at `tools/dof_proof.gd` can be a REFERENCE for API shape (it's a scene-script test, not a
   live-node test). DOF must be subtle — this is Pali's gate: "barely visible but you feel it".
   If the DOF makes the full-hamlet render test (12 checks) fail on a stability/pixel-stable
   assertion, that assertion's tolerance can be widened by up to 2x (document it, and say why in
   notes.md). The cottage_detail test (33 checks) MUST stay 33/0 — do NOT touch it.
4. **Keep grade at v5.3 baseline** (baseline saturation 1.06, contrast 1.04, sky_top #7f9db5,
   horizon #e8c98e, fog #e6c193 density 0.0021). Do NOT re-tune the grade — Pali approved the closeup.

## Hard rules
- Do NOT modify any test file except possibly the `m2_hamlet_composition_render_test.gd` tolerance
  for the DOF assertion ONLY (and only if step 3 requires it).
- Do NOT add new archetype types, new node types, or new scene .tscn files.
- Every godot command: explicit timeout >= 600, and for render commands add `DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 --renderer mobile`.
- Commit after each landed unit (git add -A; git commit -m "step3 <n>: <what>"). Do NOT let uncommitted work sit >15 min.

## Verification gate (run ALL before you finish)
From the repo root:
  G=/opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64
  timeout 600 $G --headless --max-fps 60 --path . --script tests/backend_test.gd
  timeout 600 $G --headless --max-fps 60 --path . --script tests/visual_lighting_profile_test.gd
  timeout 600 $G --headless --max-fps 60 --path . --script tests/m1_acceptance_test.gd
  DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 600 $G --max-fps 60 --path . --renderer mobile --script tests/cottage_detail_render_test.gd
  DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 600 $G --max-fps 60 --path . --renderer mobile --script tests/m2_hamlet_composition_render_test.gd
  DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 600 $G --max-fps 60 --path . --renderer mobile --script tests/facade_depth_render_test.gd
PASS = every one prints `checks=N failures=0` and exit code 0.
(The roof test `joined_roof_course_render_test` has a KNOWN pre-existing 4-fail at HEAD — do NOT chase it, just note it in notes.md.)

## Final report (put this exact block at the end of your last message)
STEP3 REPORT:
- Camera clamp: file:line, what changed, min/max pitch before/after
- Hamlet extension: what was placed, how many new static nodes, total draw-call delta
- DOF: CameraAttributesPractical params, which file, how much visible on the hamlet capture
- Grade: confirm unchanged (paste baseline values)
- Tests: last checks=failures line for each of the 6 tests above
- Git: commit shas (short) in order, branch name
