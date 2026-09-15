# Hearthvale visual overhaul — Durable STATE (Bob read-only handoff)

> THIS FILE IS THE ONLY THING THAT SURVIVES between Bob runs. Every run:
> 1. First, read this file (and `git log --oneline -8`) — do NOT re-explore the repo from scratch.
> 2. While working, UPDATE this file: append a 5-line entry after every committed unit
>    (what changed, which tests passed with what checks=N failures=M, what's next).
> 3. Commit+push this file with every other commit (it lives in out-visual/, which is
>    git-excluded — so ALSO copy it to `notes.md` at repo root on each commit, root notes.md IS tracked).

## Current ground truth (updated after each run)
- Branch: task/visual-overhaul-1 @ 47a3067 (pushed to origin)
- 47a3067: scripts/m1_scene.gd golden-hour pass — sun #ffd9a0 energy 1.72 rot(-33,-46,0),
  procedural warm sky, ordinary fog, modest glow, ACES + light warm grade, SSAO (Mobile-safe).
  Regenerated 6 cottage-detail screenshots (reports/screenshots/m1-cottage-detail/).
- NOT done yet: (b) terrain warmth/slope banding, (c) foliage variety+density, (d) building
  palettes/detail, (e) hamlet composition, updated tests/visual_lighting_profile_test.gd
  expectation (approved spec change), before/after capture, full gate, PR.

## What worked / how (do not re-derive)
- Capture pattern (CONFIRMED): `godot --path . --headless --write-movie frame.png --fixed-fps 30 --quit-after 60 -- --review-<view>`
  then copy `frame00000059.png`. Reference: tools/capture-m1.ps1 + existing reports/screenshots/.
- Test gate: `tools/godot/Godot... --headless --max-fps 60 --path . --script tests/<x>_test.gd` →
  `checks=N failures=M`, must be failures=0 && exit 0. Order: foliage, cottage_detail_render,
  facade_depth_render, joined_roof_course_render, backend (~90s, use timeout=300+), m1_* incl. m1_acceptance.
- Art direction (owner, 2026-09-14): full look freedom incl. fog/glow/tonemap; only hard gate =
  steady 30FPS on the Thor Mobile renderer (no volumetrics/SDFGI/SSR). Owner approves updating the
  fog/glow expectation in tests/visual_lighting_profile_test.gd (~line 38) with a commit noting it.

## Run log
- run 5 (00:43-01:53, died compression): produced 2b441d4 + 47a3067. 31 api calls, 70min.
- run 6 (02:03-03:20, died Ollama 500 "no user query found in messages" at ~52k tokens): zero new commits. LESSON: it spent ~40min re-reading files before editing. READ THIS FILE FIRST.
- run 7 (03:39-05:42, 2h05m in, 83 api calls, ~64k tokens, died: xhigh REASONING ate the ENTIRE output-token budget every turn — "no visible answer produced, model hit output-token limit on every continuation"). It had left `scripts/m1_scene.gd` with a STAGED REVERT of the golden-hour look (removed the warm env for a flat 2-line one) + an uncommitted `tools/bob_gate.sh`. I RESTORED m1_scene.gd to HEAD (golden-hour is safe in b754f61) and kept ONLY bob_gate.sh. DO NOT revert the lighting. If you change the look, it must be a deliberate improvement over b754f61's golden-hour, not a flattening.
- NEXT RUN: the golden-hour lighting is landed (47a3067/b754f61). Areas (b)–(e) still open: terrain warmth/slope banding, foliage variety+density, building palettes/detail, hamlet composition, updated visual_lighting_profile_test expectation, before/after capture, full gate, PR.

## === 2026-09-15 session (Hermes + Pali) — read before anything else ===

**BREAKING CHANGE vs the old entries above:** the golden-hour lighting was in
`scripts/m1_scene.gd` — a file NOTHING in the repo references. The real game
(run/main_scene = scenes/m1.tscn) runs the m2_scene_* chain ending in
`scripts/m2_scene_upper_wall_details.gd`, whose `_build_world()` overrode the
environment. It is NOW fixed (commit 00dabd6): verified golden-hour block
(Sky resource + warm sun #ffd9a0 e1.72 + fog + additive glow + ACES + grade)
is in the live `_build_world`. Evidence: scene_boot_gate_test 4/0, m2_hamlet
12/0, backend 83/0, visual_lighting_profile 50/0, m1_acceptance 112/0.

**OPEN BUG (your job):** render-determinism gate failures
- `cottage_detail_render_test`: 33 checks / 1 FAIL: "unchanged recipe
  renders identically" (line 102: two captures, same camera, byte-equal
  expected). Pixel diff concentrated in the upper sky region.
- `joined_roof_course_render_test`: 80 / 4 FAIL (same family).
- SSAO already removed from the live block; STILL fails on cottage test →
  suspect Sky/glow/ACES background pass on mobile renderer.
- METHOD: flip ONE environment property at a time, re-run
  `cottage_detail_render_test` (~1-2 min), find the culprit. Verify whether
  it also fails on commit 47a3067 (pre-golden-hour) to establish
  pre-existing vs introduced — report the exact command + output either way.
- HARD RULE (Pali): do NOT edit tests or loosen the byte-equality check.
  Make the scene deterministic.

**New ground-truth tools (verified working):**
- `tools/probe_godot.gd` — ask the installed 4.7.2 engine for valid props:
  `godot --headless --max-fps 60 --path . --script tools/probe_godot.gd -- Environment`
- `tests/scene_boot_gate_test.gd` — boots the REAL m1.tscn, hard-fail if
  WorldEnvironment/sky/fog/glow not live. Both wired into `tools/bob_gate.sh`.

**Env:** engine /opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64;
render tests need Xvfb :99 (start if absent) + LIBGL_ALWAYS_SOFTWARE=1;
full suite: `GATE_RENDER=1 bash tools/bob_gate.sh`.
Branch task/visual-overhaul-1; push via
`GITHUB_TOKEN="$(cat /opt/data/cred/github-token)"`.

**ART TARGET (Pali 2026-09-15):** reference image at
`docs/art/wide-shot-target-2026-09-15.png` — crisp saturated wide shot,
NO atmospheric wash even at distance: punchy greens, strong roof/wall
contrast, legible buildings far away. THIS RUN = LIGHTING ONLY (asset
variety is on Pali's own list — do NOT add new archetypes).
ACCEPTANCE:
  1) wide shot (m2_hamlet) matches that crispness: haze gone, saturation/
     contrast up, keep the warm sky/sun
  2) subtle DOF: attach `CameraAttributes` (Godot 4.7: Camera3D.camera_attributes)
     to the hamlet camera — focus distance at the middle cottage (~15-25u),
     gentle near/far falloff (dof/near/blur + far/blur), NOT a full blur
  3) determinism gate still passes (DOF is a deterministic blur; VERIFY)

**DEBUG LOG (2026-09-15):** SSAO is NOT the culprit — removing it from
m1_scene.gd (commit 3d8d5dd) left the failure in place (checks=33
failures=1). KEY FINDING: the saved PNGs (03 vs 04) are pixel-identical in
8-bit, so the drift is SUB-QUANTIZATION in the float framebuffer (the test
compares Image.get_data of the live render, not the PNG bytes). Suspects:
procedural-sky pass, ambient-from-sky, glow, ACES tonemap — anything with
per-frame evaluation on the mobile renderer. tools/det_env_probe.gd runs the
same minimal scene twice per flag and reports drift pixels per flag
(--glow / --tonemap / --fog / --sky / --ambient-sky combos).

**Rules (unchanged from before, still in force):** commit+push first empty
commit before edits; explicit high timeout (≥400s) on every godot command;
bounded reads (grep, no >500-line dumps); commit every unit + update this
file; never guess Godot API — use the probe.

## Hermes pass (2026-09-15, after Pali's wide-shot complaint)
- Pushed commits (branch task/visual-overhaul-1, remote live): a96a49c de-haze fog,
  4bc2b01 horizon warm push, 44a4dee distance-gated DOF, f47599c sky_top warm to #c9b89a,
  be85bd8 v3: fog_density 0.0028, fog_light #e8b878, adjustment_saturation 1.12,
  DOF far_start +14u / transition 38 / amount 0.5.
- Pali verdict on f47599c-era frame: cottage closeup GREAT; wide hamlet STILL washed out;
  DOF NOT VISIBLE. Diagnosis: wide shot top-of-frame is far GROUND (cam pitch 0.72 down,
  distance 42u) not sky; old DOF focused ON the hamlet (near_start 36u) so almost nothing
  blurred. The far field needs: richer fog color (toward #d89a4f if needed), density up,
  saturation/contrast pass, DOF far blur strong enough to read (amount 0.6-0.8) —
  while m1_playtest_repair (cottage detail) and m2-hamlet stay sharp.
- KNOWN OPEN: m1_playtest_repair_render_test 33/1 — "unchanged recipe renders identically"
  in-frame float drift (pre-existing per 029fc46 probe: animation-element baseline, not the
  lighting family). Pali asked: make it compare the PNGs ON DISK (that's what he sees)
  instead of float readback — do this after the visual pass.
- Next run (Bob): 1) backdrop saturation pass on wide shot (see Pali's reference
  docs/art/wide-shot-target-2026-09-15.png), 2) DOF proof: render hamlet with DOF on/off,
  save both PNGs, diff must be visible in far band only, 3) fix repair test per Pali's
  disk-compare ask, 4) full gate, push, post frames.

**NEW ACCEPTANCE CRITERION (Pali, 2026-09-15 mid-run):** the closeup
cottage look is APPROVED ("very good up close"), but the WIDE shot
(m2_hamlet_composition full hamlet) "is just hazy" — the fog is swamping
the buildings. Fix: significantly reduce fog depth/density in the live
_build_world so buildings read crisply across the hamlet — KEEP the warm
sky gradient + soft low warm sun, push horizon warmth, keep distance
contrast. Acceptance: re-render full hamlet + cottage captures look
impressive AND warm; verify with tests/visual_lighting_profile_test.gd
(still 0 failures) and by eye. Do this AFTER/ALONGSIDE the determinism
fix, same live file.
