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
