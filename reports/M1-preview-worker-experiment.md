# M1 terrain preview worker — measured experiment

2026-09-07. Branch `fix/m1-terrain-strength-preview`. **Experimental; not ready to merge or export.** Preview-side main-thread stalls are greatly reduced, but continuous-input preview availability fails the intended interaction. No new APK or Thor test.

Tested code: `7b7c19f4adb00913e6a9c1bb3a7299b65a9d5504`, tree `426ede5771276a3d0518043bdf926f4e1ca5a01a`. Native Windows CI [run 34165865770](https://github.com/palinalif/Hearthvale/actions/runs/34165865770) completed successfully. Artifact `10034133515` contains exact tracked source, complete logs and synthetic render captures; archive SHA256 `d9513c91752ab247300fcf7abefca2cb224b539cabedbe46954af4783f4fc5a6`. Extracted receipts are preserved in [performance/M1-preview-worker-7b7c19f.log](performance/M1-preview-worker-7b7c19f.log). The documentation commit following this tested code does not change runtime or tests.

## What changed

- `sculpt_preview_snapshot.gd` captures an owned native TYPE buffer covering the brush and halo in the two perpendicular axes, and the complete facing axis. This retains contiguous solid/void semantics without cloning the whole world. Active frontier metadata is copied, with long histories bounded to the local footprint. No live scene node or live editable buffer is read by the worker.
- `sculpt_preview_job.gd` allows one worker and no queued backlog. Completed results require matching aim, tool, settings, terrain state and context generation. Menus invalidate without joining a running job. Only shutdown may wait. Expensive temporary dictionaries and snapshots are destroyed on the worker before handing compact output back to gameplay.
- `sculpt_occupancy_runs.gd` uses native local copying, remapping and rotation, followed by bounded byte searches. `sculpt_preview_query.gd` accelerates only frontier seeding; actual edit decisions still use the original backend integrators through the read-only adapter. All six facing directions and 8-/16-bit material occupancy have native parity tests.
- `terrain_preview_buffers.gd` packs three MultiMesh buffers off-thread. `terrain_edit_preview.gd` publishes them in bulk instead of invoking per-instance setters. The shader, complete candidate cells, hatching, addition geometry and reach styling are retained.
- The actual M1 scene hides stale exact-cell overlays, keeps the target marker/useful plane, and explicitly labels pending computation. Unchanged idle results remain cached. This honest pending state does not solve the availability problem below.

Godot, Voxel Tools, native terrain representation, sculpt integration, strength anchors, planting, building records, world dimensions and save formats are unchanged by this experiment. No runtime networking, external model or new plugin is introduced. `master` remains at the predecessor build `2da7b7e`.

## Native CPU measurements

All following timings come from the one successful Windows runner above, not the Thor. Each cold/moving/held row contains five requests. **Moving and held rows in this table are step-and-settle microbenchmarks:** change the input once, then wait for that exact result. Real continuously changing input is measured separately below.

| Radius / phase | Main-thread capture/start, ms | Worker query, ms | Worker packing, ms | Result available, ms | CPU publication, ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 / cold | 0.177–0.453 | 11.207–12.271 | 1.337–1.369 | 16.616–17.281 | 0.018–0.039 |
| 2 / moving | 0.167–0.284 | 11.405–12.266 | 1.290–1.340 | 15.926–16.677 | 0.017–0.029 |
| 2 / held | 0.279–0.464 | 7.022–7.902 | 1.297–1.341 | 12.081–16.026 | 0.026–0.031 |
| 8 / cold | 2.139–2.678 | 194.557–201.705 | 21.507–27.089 | 230.913–249.941 | 0.071–0.185 |
| 8 / moving | 2.165–2.351 | 192.570–200.648 | 21.424–23.202 | 233.007–249.209 | 0.074–0.082 |
| 8 / held | 4.178–4.769 | 121.348–125.387 | 21.423–24.081 | 171.288–171.718 | 0.069–0.104 |

The same run measured the original synchronous query at 21.641 ms for radius 2 and 686.037 ms for radius 8. Those are single control samples, not distributions. Earlier runner samples were approximately 17.6/571.4 ms; do not treat cross-run differences as a product regression or improvement.

Full candidate counts remain 793 and 12,849. Vertical snapshots contain 860,672 and 9,609,728 bytes respectively; these are fixture-specific voxel-copy sizes, not peak allocation including temporary buffers. Horizontal maximum-radius memory/timing has not been benchmarked here. A long-history fixture copied 1,681 local fronts from 147,456 live fronts in 1.160 ms, retaining retired fronts.

All existing CPU service gates passed: capture/start p80 below 12 ms, nonblocking poll p95 below 2 ms, CPU publication p80 below 4 ms. With five samples, the implemented p80 selects the maximum. Measured poll p95 was at most 0.295 ms across these rows. These are narrow preview-service costs, not complete gameplay frame time. Headless publication uses the dummy renderer: **its timings are not GPU upload or draw timings.** Result availability includes polling/scheduling and is not the same as worker CPU time.

## Blocking result: continuous input starves the exact overlay

The live test changes the aim or advances a held stroke on every frame for 90 frames, polling without waiting for each request. The strict whole-request key changes before results can be published.

| Radius / input | Frames with a current exact preview | Preview service p95 / maximum, ms | Recovery after input stops, ms |
| --- | ---: | ---: | ---: |
| 2 / moving aim | 0 / 90 | 0.586 / 0.846 | 16.526 |
| 2 / held Dig | 1 / 90 | 0.708 / 0.843 | 14.343 |
| 8 / moving aim | 0 / 90 | 2.500 / 2.701 | 416.682 |
| 8 / held Dig | 0 / 90 | 4.816 / 5.062 | 268.257 |

**This is not acceptable continuous preview behaviour, including at the default radius.** The game is no longer waiting synchronously for each complete query in this path, but the exact ghost/hatching is mostly absent until input settles. A green run is not an interaction pass: the live test checks correctness of anything published and recovery afterward, and explicitly reports availability as NOT ESTABLISHED. Its zero failure count must not be presented as meeting the visibility requirement.

Do not fix this by accepting outdated cells as current, moving the old mesh to the new cursor position, reducing the footprint silently, or adding more workers. The next experiment should decouple reusable local surface data from the changing aim, or incrementally update independently validated regions. Current input, edited cells, cave boundaries, smoothing neighbours and reference planes still need exact parity. Whole-brush request invalidation must be replaced with something that can actually remain current during continuous input. This design is proposed, not implemented or validated.

## Tests and rendered evidence

The eight preceding suites remain, with their original assertions: profile 118, neighbourhood 410, smoothing 23, sculpt 188, scaled backend 29, strength 37, next-layer 635 and M1 scene 24. The scene test now waits finitely for an asynchronous current preview rather than requiring it in one frame; its visibility, HUD, cancel, menu, planting and cottage-placement assertions remain.

Added native suites: occupancy runs 15,408; snapshot/job/buffer parity 1,386; CPU performance 54; continuous input and bounded long-history diagnostics 8. **Total: 18,320 headless assertions, zero failures.** The continuous availability results above remain a release blocker regardless of this total.

The separate non-headless test initialized Godot's actual **Mobile renderer with D3D12 on Microsoft Basic Render Driver**, a software adapter. Four checks passed with an empty stderr log. The 1028×578 synthetic bulk-buffer and former per-instance-setter captures were pixel-identical, and both differed from the blank frame. The capture was visually inspected: removal hatching and outlined additions appeared in their respective halves. This verifies the bulk buffer layout and existing shader path for that fixture; it is not integrated M1 art approval or hardware GPU performance evidence. The successful run did not test Vulkan.

Reproduce native checks with `./tools/test-terrain-ux.ps1`, then rendered parity with `./tools/probe-terrain-preview-render.ps1`. The workflow retains source, logs and captures. The editing container had no Godot/PowerShell or direct GitHub networking; native execution occurred on GitHub's Windows runner, not locally. Downloaded artifact source was compared with the local changed scripts and matched after line-ending normalization; the archive digest and capture pixel parity were independently checked locally.

## Failed iterations retained in history

`5e792e6` failed import because a snapshot field collided with `RefCounted.reference()`. `0678299` fixed that and introduced native searches but had a test indentation error. `aff7ddb` fixed the test and exposed an unavailable `VoxelBuffer.duplicate` binding. `c0d21d9` switched to the exposed copy API; remaining occupancy failures identified uniform-buffer rotation behaviour. `6b217fb` handled uniform occupancy and passed correctness, but main-thread result destruction failed two polling-cost checks. `ca8aaba` moved heavy destruction off-thread and passed all headless tests; its synthetic pixel checks passed after D3D12 fallback, but the workflow correctly failed on logged Vulkan/audio initialization errors. `7b7c19f` explicitly selected D3D12 and Dummy audio, bounded long-history copying, and passed the complete workflow without relaxing the error or CPU-budget gates.

Historical erratum: the earlier report misdescribed pre-worker run 34162761366. It actually recorded 3,136 checks / 1,107 failures, primarily axis-0/axis-2 occupancy and seeding parity, with radius-8 cold/warm/build timings 168.033/118.964/16.179 ms. The earlier zero-assertion-failure/remap-error narrative and 538.684/217.981/43.162 numbers are corrected in that report. The failed experiment was already reverted at 128db487; no baseline assertions were removed by this worker experiment.

## Remaining acceptance

Resolve continuous-input starvation and maximum-radius response latency, then measure complete moving/held M1 frames, rendered maximum-radius publication/draw costs and horizontal-facing workloads. Add explicit availability/age budgets once the next design exists; do not hide failed experience behind lower-level gates. Independent review of the asynchronous architecture, new-build Android startup/signing/save-update checks and physical Thor playtests are **not run**. Existing safety regressions pass, but no new physical focus/disconnect/controller evidence is claimed. Retain the last shared APK, signing identity and player saves; do not export or merge this experimental branch yet. M0 gaps remain open and M1 is not complete.
