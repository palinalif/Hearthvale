Hearthvale visual pass — finish the WIDE SHOT + DOF + one test fix.
Repo: /opt/data/sandboxes/Hearthvale-visual (branch task/visual-overhaul-1, HEAD f89d453)
Imports already done (.godot exists). Xvfb :99 + LIBGL_ALWAYS_SOFTWARE=1 for render tests.
Every godot command: explicit high timeout (>=400s) or it dies at the default cap.

READ FIRST: notes.md "Hermes pass" section (current env values + diagnosis).

STATE: Pali APPROVED the cottage close-up. He REJECTED the wide hamlet shot:
"too washed out" and "I don't see the DOF at all".
Art reference: docs/art/wide-shot-target-2026-09-15.png — crisp, saturated, no haze,
punchy greens, strong contrast, warm sky. Diagnosis is in notes.md: the wide shot's
top-of-frame is far GROUND (camera pitched 0.72 down), not sky — so it's the fog veil +
low saturation that washes it; and the old DOF focus band sat ON the hamlet so almost
nothing blurred.

TASKS (this order), each committed + pushed + noted in notes.md:

1) WIDE SHOT saturation/depth pass — scripts/m1_scene.gd _build_world:
   push fog_light_color toward #d89a4f..#e0a050, fog_density 0.0028..0.0045,
   adjustment_saturation/contrast 1.1..1.25 while shadows keep depth, sky gradient intact.
   Iterate: run tests/m2_hamlet_composition_render_test.gd, open
   reports/screenshots/m2-hamlet/full-hamlet.png and compare to the reference.
   Stop when the frame is clearly warmer, more saturated, far terrain shows depth —
   not a flat cream wall. Also re-render cottage detail and confirm it's still approved.

2) DOF that is VISIBLE in the wide shot: keep near band sharp (village) but make far
   ground (beyond ~60u) clearly soft — raise dof_blur_amount to 0.6..0.8, pull
   far start to camera+10..14, transition 25..40. PROOF: render the hamlet with DOF
   force-disabled (comment the block) and with it enabled, save both PNGs, then compute
   per-region mean abs pixel diff (far region vs village region) in python/PIL. The far
   region must differ; village must stay near-identical (within ~2-3 mean abs). Keep
   both proof PNGs in the commit (e.g. reports/dof-proof/).

3) m1_playtest_repair_render_test (33 checks / 1 failure "unchanged recipe renders
   identically"): Pali asked to compare the PNG FILES ON DISK instead of the in-frame
   float readback (that's what he sees). Change that one test's repeat-capture check to
   save both captures to PNG and compare saved-file bytes (or near-identical within the
   repo's existing <=4px tolerance used by the hamlet gate). Keep all other checks.
   Must reach 33/0.

4) FULL GATE: run the suite per notes.md (foliage, cottage_detail, facade_depth,
   joined_roof_course, backend ~90s, m1_acceptance, m1_playtest_repair, m2_hamlet,
   visual_lighting_profile, scene_boot_gate). All failures=0, exit 0.

5) Push everything to task/visual-overhaul-1 (token: GITHUB_TOKEN from
   /opt/data/cred/github-token), leave the latest full-hamlet + cottage-detail PNGs in
   reports/screenshots/, and write a 10-line final summary in notes.md + your answer:
   final env values, DOF proof numbers (far vs near diff), suite results, pushed commit
   hashes.

HARD RULES: never loosen a test's real assertions except the disk-compare change in
task 3 (that change is what Pali requested); no new buildable entities; no volumetrics/GI
/SSR (Mobile renderer, Thor 30fps gate); commit+push before any long edit; bounded
reads (grep, no >500-line dumps); update notes.md after every unit.
