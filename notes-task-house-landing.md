# notes.md — task/house-landing (house placement finishing: tuft ring + dirt rim)

Durable state file. Read FIRST on resume. Format per unit:
what changed / checks=N failures=M / what is next.

## U0 — branch created (crash-resume artifact)
- what changed: branch `task/house-landing` created off `master` (6ae02f9);
  notes.md stub added. No source edits yet.
- tests: none run yet.
- next: recon of owned files + placement/commit hooks, then part 1 (tuft ring).

## Known pre-existing master failures (inherited from sibling runs, baseline — DO NOT fix)
- cottage_detail_render_test.gd: "FAIL: unchanged recipe renders identically" (checks=33 failures=1)
- m2_hamlet_composition_render_test: SCRIPT ERROR Invalid access to 'points' (no checks line)
- tests/scene_boot_gate_test.gd does not exist on master although the local
  tools/run_render_gate.sh helper references it (helper is untracked/injected).

## U4 — pickup by Pi (2026-09-17): rebased onto main, re-PR'd
- context: PRs #21/#22/#23 were found closed unmerged (not intentional) and their
  base branch `master` had been deleted from the remote, so GitHub cannot reopen
  them ("State cannot be changed. The master branch has been deleted.").
- changed: rebased this branch onto `main` (f610176); notes moved from root
  `notes.md` (owned by the visual-overhaul handoff on main) to this file
  `notes-task-house-landing.md` to end the permanent conflict. No feature-code
  changes.
- tests (local headless, stock Godot 4.7.2 — no native voxel module here):
  house_edge_foliage_test 30/0 ok:true; house_dirt_rim_test 32/0 ok:true;
  house_landing_scene_test FAIL "native backend ready" (environmental: same
  limitation on plain main; native-backed legs go to CI).
- delivery: forced push d88f048; new PR https://github.com/palinalif/Hearthvale/pull/26
  (base main).
- next: CI green on #26; user visual approval.
