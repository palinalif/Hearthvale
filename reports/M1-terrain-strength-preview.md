# M1 terrain strength and preview — implementation checkpoint

2026-09-07. Branch `fix/m1-terrain-strength-preview`. Status: strength implemented and native-tested; preview correctness prototype implemented and native-tested; preview performance acceptance NOT met. No new APK. Do not describe both points as completed.

## Scope delivered

The user's requested predecessor merge was completed first: master fast-forwarded to the old playtested branch at2da7b7e, preserving all16 commits. The new terrain branch starts there.

Commit293f873 changes only the user-facing strength route and its tests: level1=1.0, level5(default)=2.0, level10=4.0 world units/sec, exponential steps within each segment. This is one-third the preceding raw6.0 default. L3 remains quarter-rate; foliage/tree records and density are unchanged.

Commita7511ae adds removal face hatching, outlined addition cells and a separately dim reach rim, using a read-only adapter over the real backend integrators. The wording is 'Next layer at current aim'; this means one transition per currently eligible column, not the next frame or final result of a continuous hold. The original voxel data, live accumulators, revisions and undo stacks are untouched by planning. Level/Slope keep their actual reference plane; Raise/Dig/Smooth do not show the old blue square. Pause/tool/building contexts hide terrain overlays. Idle unchanged plans and meshes are cached.

## Actual tests

Native Windows CI run34161535202 passed the strength change. Combined run34162179626 passed:

| Suite | Checks | Failures |
| --- | ---: | ---: |
| sculpt_brush_profile_test | 118 | 0 |
| smooth_neighbourhood_test | 410 | 0 |
| sculpt_smoothing_test | 23 | 0 |
| sculpt_test | 188 | 0 |
| m1_scaled_backend_test | 29 | 0 |
| sculpt_strength_test | 37 | 0 |
| sculpt_next_layer_test | 635 | 0 |
| m1_terrain_ux_test | 24 | 0 |

New coverage includes preview-to-native next-layer parity for five tools and wall/ceiling directions, read-only active/idle plans, void boundaries, undo/redo, settled smoothing, the actual exported M1 scene, menu visibility/cancel, planting and cottage-duplicate compatibility. The next-layer parity test gives the native integrator one cell of credit for each eligible column, matching the explicitly labelled preview horizon. It does not claim equal time-to-edit for different falloff weights.

Headless passes do not validate the visible shader result, actual GPU draw costs, maximum-radius interaction comfort, Android startup, save/signing update compatibility, or Thor performance. Those remain not run for this branch.

## Performance blocker and rejected experiment

A single CI diagnostic on a fine.125-unit grid measured cold Dig planning at17.553 ms (radius2,793 cells) and571.356 ms (radius8,12,849 cells). This synchronous work is unacceptable for the stated no-lag requirement. These are runner CPU timings, not Thor measurements or stable averages.

Commit67b6104 tried bounded native occupancy snapshots/remapping. Run34162761366 failed because the native extension logged two Invalid input count errors in remap_values_u8 plus fill_area/get_value bounds errors. The wrapper correctly failed the run despite the new test printing3136 checks /0 failures. Later suites were not executed after that gate. It also measured cold538.684 ms, warm217.981 ms and mesh-build43.162 ms at radius8, so accepting only the assertions would not fix the performance issue.

The follow-up commit backs out that experiment to the exact passing a7511ae implementation/test tree. No existing success criteria were weakened; the unsuccessful helper and its test are removed together. The recorded failed run remains part of the history.

## Remaining before joint playtest

1. Bound query and mesh-publication work at both normal and maximum radii; measure repeated cold, moving and held input. A lower update frequency alone does not remove a long synchronous stall.
2. Any worker must read an immutable bounded snapshot, not the live editable buffer; generation checks must reject stale aim/tool/stroke/revision results. Pending or partial visual feedback must be labelled honestly.
3. Retain exact candidate parity and active-front cave rules; test cancellation, undo/redo, focus loss and controller disconnect. Check the visible shader and face orientation in the actual Mobile renderer.
4. Resolve stable Android signing, deliberate versioning and private Drive delivery, then produce one APK containing both terrain improvements. Preserve existing APKs/saves. Device approval remains the user's decision.

Reproduction: `./tools/test-terrain-ux.ps1`. Workflow `terrain-ux.yml` archives exact tracked source and full logs. The editing container had no Godot runtime; its source-level checks are not counted as native execution.
