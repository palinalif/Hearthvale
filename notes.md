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
