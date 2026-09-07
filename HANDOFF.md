# Hearthvale — current M1 handoff

Updated 2026-09-07. Read AGENTS.md and the user's latest request first. M1 is not complete. The full preceding handoff is retained at `docs/history/HANDOFF-before-terrain-ux.md`; do not reread it unless its baseline details are needed.

## Repository and approved work

The default branch is **master**, not main. At the user's explicit request, the previous `fix/m1-sculpt-feedback` branch was fast-forward merged into master at `2da7b7e926b1ea73cbfa8418948160d52d7646aa`. That retains the smoothing, rounded/plateau brush profiles, wall-relative attachment ghosts, free cottage duplication and APK workflow history. The user playtested that APK on the Thor and liked the sculpting behaviour but found its strength excessive.

Current work branch: **fix/m1-terrain-strength-preview**, created from that merged master. Do not merge this new work or ship an APK while its performance acceptance remains unresolved.

Only these two priorities are approved for this batch:
1. Displayed strength 1–10 with 5 as default; raw rates 1, 2 and 4 world units/sec at levels 1, 5 and 10. Retain quarter-speed precision and leave planting alone.
2. Accurate, inexpensive next-layer terrain feedback: removal hatching, ghost additions, a separate surface-following reach cue, and useful Level/Slope target planes. Do not reintroduce sculpting lag.

Subsequent priorities remain building-centred editing camera, window geometry consistency, user-reviewed cottage UX, finer decorative resolution prototype, river and trees. None of those is implemented in this workstream.

## Current implementation and evidence

- `293f87397d32fe6bb1acd70241ed4bf5539ee865`: gentler strength and exponential interpolation through the three agreed anchors. New `sculpt_strength.gd` and `m1_scene_terrain_ux.gd`; the exported `scenes/m1.tscn` uses the latter above the existing placement subclass. CI run 34161535202 passed. The new strength test has 37 checks, including actual inherited stroke settings for all five sculpt tools and precision.
- `a7511ae88f6f40ad98f8a9ca66c360002d09c29e`: functional read-only preview prototype. `sculpt_next_layer.gd` reuses native backend integrators with intercepted writes; `terrain_edit_preview.gd` draws three batched layers. Exact footprint, one-cell credit per eligible column, not an end-of-hold prediction. Idle plans are cached. Menus hide the preview; planting retains its prior preview.
- CI run 34162179626 passed all eight suites: profile118, neighbourhood410, smoothing23, sculpt188, scaled29, strength37, next-layer635, scene24 (all zero failures). These are native headless checks, NOT actual shader/render, Thor performance or visual approval.
- Profiling found a blocker: cold fine-grid Dig queries took 17.553 ms at radius2 / 793 cells and 571.356 ms at radius8 / 12,849 cells on that Windows CI runner. These are single diagnostics, not statistically robust benchmarks. Do not ship this synchronous preview as an accepted performance solution.
- `67b6104e473f2a2175285221cffba44b95fdd6b6` attempted bounded occupancy-run acceleration. Run 34162761366 failed native remap/bounds checks despite zero assertion failures; timings did not establish an improvement. The follow-up restores the exact a7511ae code/test tree and records this failure. It removes the unsuccessful index helper/test, not any established baseline assertions.

## Next engineering task / acceptance

Finish point2's performance before a combined Thor build. Separate cold querying, moving/held querying and mesh publication costs. Avoid synchronous whole-brush rescans and per-instance API loops at maximum radius. Any incremental or worker implementation must use immutable bounded snapshots (not concurrent reads/writes of the live voxel buffer), reject stale results on aim/tool/revision/context changes, and visibly distinguish pending computation from a current edit prediction. Do not merely throttle a half-second synchronous operation or silently show sparse cells as a complete prediction.

Reuse the real tool decisions and retain parity in all six facing directions, disconnected caves, smoothing at rest, cancel/undo/redo, and the actual exported scene. Add meaningful budgets and repeated cold/moving/held timing receipts. Passing correctness alone is insufficient. Verify shaders and geometry on the actual Mobile renderer before exporting.

Run `./tools/test-terrain-ux.ps1` on the pinned Windows environment; `.github/workflows/terrain-ux.yml` runs it and retains exact source plus logs. The editing container had no Godot/PowerShell and direct GitHub networking failed; no native tests ran there. Source was acquired through an authenticated GitHub Actions artifact. No external model or network is added to gameplay.

## Runtime, saves and artifacts

Pinned Godot4.7.2.stable.official.ed1daf0bf, matching templates, Voxel Tools v1.7x (75d3c6d996ed2331c80edcd8c3ebc947afc0f041). Mobile renderer, native384×256×384 at .125 units, world48×32×48, raw72MiB. Dependencies, visible grid, world bounds, building/planting data and save formats are unchanged by this batch. Preserve original legacy checkpoints, manual overrides and all existing transactional contracts.

No new APK or device test for the current branch has been produced. Last shared APK is `hearthvale-m1-thor-feedback.apk` from2da7b7e, workflow34155044241, artifact10030682437; private Drive file1NgNtuoTxEmpMo3Ac0PlNUtfENK9otRoI. It uses an ephemeral CI debug key, not established signing continuity with the original local builds. Resolve update-compatible signing before the next build. Never uninstall or erase player saves to bypass signature errors. Use a new versioned filename, verify the actual APK, upload privately to Drive only with a completed metadata readback, and distinguish export verification from Thor playtest approval.
