# Ground foliage review candidates — 2026-09-08

Three ground-foliage replacements were authored and edited through the registered
`hearthvale-magicavoxel` MCP server, following the tree review workflow. Gameplay
still uses its current procedural assets. Cottage flower boxes are outside this pass.

| Candidate | Triangles | Current counterpart | Bounds size |
| --- | ---: | ---: | --- |
| Grass | 206 | 216 | 1 × 0.75 × 0.75 |
| Wildflowers | 226 | 276 | 1 × 0.625 × 0.875 |
| Leafy plant | 232 | 216 | 1 × 0.625 × 0.875 |

Sources: `assets/source/magicavoxel/hearthvale_foliage_{grass,wildflowers,leafy}.vox`.
Matching OBJ, MTL, provenance receipt and baked Godot `.res` files live in
`assets/models/magicavoxel/`. `foliage-candidates.authoring.json` records actual MCP
operations and snapshot iterations. Raw output remains in ignored `.tools/magicavoxel`.
The VOX → greedy OBJ → import → matte baked `.res` pipeline preserves palette groups.
Rest geometry remains cubic on the 0.125 grid, centered on the declared source
volume and grounded at Y=0. Every connected component reaches ground.

Grass uses staggered upright blades and low outward leaves; wildflowers use three
uneven pink blooms with cream centres; the leafy plant spreads around a low core.
Snapshot review caught and connected a detached leaf tip. Actual Mobile review
showed raised flower centres reading as candles; an MCP edit lowered them into
the petal planes before final export and capture.

`scenes/foliage_wind_preview.tscn` compares current foliage above new foliage.
Run with `-- --context` to see the new set beneath the approved trees at true scale.
Space pauses, W toggles wind, Escape closes. The shared affine wind shader keeps
roots fixed and greedy mesh seams closed, using independent phases and gentle
strengths 0.035 / 0.025 / 0.030. Wind adds no geometry and changes no source data.
The user explicitly requested this render-only off-grid animation trial.

Evidence:

- `screenshots/foliage-candidates-comparison.png`: labelled actual Mobile comparison.
- `screenshots/foliage-wind-preview.mp4` and `.gif`: close comparison, 12-second loop.
- `screenshots/foliage-wind-context.mp4` and `.gif`: same loop at tree scale.
- `logs/check-foliage-asset.log`: 54 checks passed, including grid, pivot, bounds,
  source hashes, matte palette groups and triangle budgets.
- `logs/foliage-meshing.log`: exact exposed-cell coverage and rooted connected
  components passed for all six tree/foliage sources.
- `logs/check-foliage-wind.log`: 21 headless checks passed.
- `logs/foliage-wind-mobile.log` and `logs/foliage-context-mobile.log`: 30 checks
  passed per actual Vulkan Mobile run on RTX 3070. Shader/CPU reference comparison,
  pause, wind-off and seamless cycle checks passed. Each video has 288 frames at 24fps.

The final full `tools/check.ps1` run passed (`logs/foliage-check-suite-rerun.log`,
exit 0, `check ok`). The first run stopped at `m1-acceptance-write-fixture` with
ten terrain/controller assertions (`logs/foliage-check-suite.log`). That test
passed alone (`logs/foliage-unrelated-acceptance-repro.log`, 112 checks) and the
full suite then passed without simultaneous preview rendering. No gameplay
script or test assertion was changed to obtain the pass. The transient failure's
cause was not established; retain the first log for future flakiness diagnosis.
The bounded independent review found no remaining actionable foliage defect.

Remaining review: player approval of these shapes/motion and real Thor performance.
Desktop Mobile rendering is not a handheld performance measurement. The current
procedural comparison has some pre-existing overlapping-face artifacts at close
range. No candidates are integrated into gameplay, and no existing assets are removed.
