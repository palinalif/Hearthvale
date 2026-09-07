# Hearthvale — current M1 handoff

Updated 2026-09-07. Read AGENTS.md and the user's latest request first. **M1 is not complete. Terrain preview remains experimental, unmerged and not ready for an APK.** Older baseline details are retained in `docs/history/HANDOFF-before-terrain-ux.md`.

## Repository and authorized scope

Default branch: `master`, still at the previous Thor-playtested `2da7b7e926b1ea73cbfa8418948160d52d7646aa`. The predecessor merge was completed before this batch. Work remains on `fix/m1-terrain-strength-preview`; the user authorized continued preview performance experiments, not additional M1 priorities or M2.

The strength change at `293f873` is retained: displayed 1–10, default 5, raw anchors 1/2/4 world units per second at levels 1/5/10, quarter-speed precision, planting unchanged. The requested preview shows complete next-layer additions/removals and a separate reach cue, with meaningful Level/Slope planes. It must not introduce sculpting lag. Building-centred camera, windows, decorative resolution, river and trees remain outside this workstream.

## Latest tested code and evidence

Code commit `7b7c19f4adb00913e6a9c1bb3a7299b65a9d5504`; successful Windows CI run `34165865770`; artifact `10034133515`. Documentation after that commit does not alter code/tests. Read `reports/M1-preview-worker-experiment.md` and its compact receipt `reports/performance/M1-preview-worker-7b7c19f.log` for exact samples and limitations.

The original read-only adapter still calls the real backend integrators; only its source type changed from Node to Object. The new `sculpt_preview_snapshot`, `sculpt_preview_query`, `sculpt_occupancy_runs`, `sculpt_preview_job` and `terrain_preview_buffers` scripts provide brush-local owned snapshots, parity-tested accelerated seeding, one worker with no backlog, and bulk MultiMesh buffers. Native gameplay editing remains unchanged. Temporary per-cell records and snapshot metadata are freed on the worker, avoiding main-thread join/replacement spikes. Long stroke history is bounded to the local brush area when copied.

The actual `m1_scene_terrain_ux.gd` now uses that job and rejects stale keys/context generations. Menus/context changes do not block on a running worker. Pending hides the exact cell overlay, preserves the small target marker/useful plane and labels the HUD explicitly. Idle current plans are cached. `terrain_edit_preview.gd` publishes three packed buffers; existing shader and full candidate detail remain.

Native headless tests: **18,320 assertions / zero failures across 12 suites**, retaining all eight preceding regression suites. New coverage includes six-direction 8-/16-bit occupancy, snapshot isolation, captured active-state independence, packed transforms, stale-result rejection and local copying of a 147,456-front history. The final rendered test separately passed **4 checks** on actual Mobile/D3D12 using Microsoft Basic Render Driver (software): bulk upload and prior setter rendering were pixel-identical, with no stderr errors. This is a synthetic fixture, not integrated M1 art approval or Thor/GPU performance.

## Measured blocker — do not treat green CI as acceptance

At radius 8, capture/start cost was 2.139–4.769 ms in step-and-settle tests, versus a 686.037 ms single control sample for the original synchronous query. The optimized full result still took about 171–250 ms to arrive. Default radius 2 requests arrived in roughly 12–17 ms. These are preview-service/worker measurements on Windows CI; headless publication cost is not GPU timing or complete gameplay frame cost.

**Continuous input starves the overlay.** Over 90 continuously changing frames: radius-2 moving aim displayed a current preview in 0 frames and held Dig in 1; radius-8 moving aim and held Dig both displayed it in 0. Preview-side main-thread service remained at most 0.846 ms at radius 2 and 5.062 ms at radius 8, but hiding stale cells means there is mostly no exact overlay until input stops. Radius-8 recovery after stopping took 268–417 ms. This fails the intended interaction at both brush sizes.

The live test's zero assertion failures only establish that anything published was current and that recovery occurred; visibility coverage is explicitly diagnostic and NOT ESTABLISHED. Do not advertise the default preview as working continuously. No assertions or error-budget gates were weakened to claim a pass.

## Next engineering task

Replace whole-brush invalidation with reusable local surface data or independently validated incremental regions, recomputing current-aim influence/changed columns with the exact native rules. This is a proposed direction, not implemented. More workers, blindly accepting stale results, relocating an old ghost or silently showing an incomplete footprint are not acceptable fixes. Preserve disconnected-cave/retired-front behaviour, smooth-neighbour dependencies, reference planes, cancel/undo/redo and all controller/menu safety.

Measure explicit current-preview availability and result age under genuinely continuous movement/held input, plus complete M1 frame costs and real maximum-radius draw/publication work. Horizontal maximum-radius performance, independent asynchronous-architecture review, Android update/signing validation and physical Thor/controller testing have not been run. Desktop synthetic rendering does not close those gates.

Reproduction: `./tools/test-terrain-ux.ps1`, then `./tools/probe-terrain-preview-render.ps1`; workflow `.github/workflows/terrain-ux.yml` retains exact source/logs/captures. No native runtime was available in the editing container; all native executions were on Windows CI. Failed iterations, including the real earlier occupancy parity failures and a correction to the old report, are documented in the worker report. Start from current code, not the reverted `67b6104` helper.

## Runtime, saves and artifacts

Pinned Godot4.7.2.stable.official.ed1daf0bf, matching templates, Voxel Tools v1.7x (75d3c6d996ed2331c80edcd8c3ebc947afc0f041). Mobile renderer, native384×256×384 at .125 units, world48×32×48, raw72MiB. Dependencies, visible grid, world bounds, building/planting data and save formats are unchanged by this batch. Preserve original legacy checkpoints, manual overrides and all existing transactional contracts.

No new APK or device test for the current branch has been produced. Last shared APK is `hearthvale-m1-thor-feedback.apk` from2da7b7e, workflow34155044241, artifact10030682437; private Drive file1NgNtuoTxEmpMo3Ac0PlNUtfENK9otRoI. It uses an ephemeral CI debug key, not established signing continuity with the original local builds. Resolve update-compatible signing before the next build. Never uninstall or erase player saves to bypass signature errors. Use a new versioned filename, verify the actual APK, upload privately to Drive only with a completed metadata readback, and distinguish export verification from Thor playtest approval.
