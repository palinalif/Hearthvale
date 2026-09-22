# Terrain and water responsiveness — 2026-09-22

Fixes on `codex/fix-terrain-water-freezes`, based on `d9333363d1ec2cea2064a158e4459b75e80dace3`.

## Changes

- Terrain history records the exact net changed cells while writing the command. Vegetation clearing and path ownership no longer scan the whole stroke's before/after bounding box on release. Sparse metadata is included in the history memory budget.
- Meadow refreshes preserve the deterministic scatter plan and invalidate terrain heights only inside the edit bounds. Unknown or skipped revisions refresh all heights. House landing decoration reuses meshes for unchanged homes outside the edit.
- Native column sampling copies one authoritative voxel column into scratch storage and scans its bytes. This avoids a native call for every empty sky voxel, preserves overhangs, and retains no height cache between queries.
- Water setters queue surface work for one bounded process pass per frame. Mesh indices remain valid across passes, telemetry counts quads without mesh readback, and unchanged waterfall meshes are reused.
- Stream footprints compute the exact union of brush stamps without repeated growing-array unions. Stream preview width now agrees with the committed footprint. Stationary lake previews do not repeatedly sample the entire lake, and stale state is still rejected at commit.
- Water and its excavated bed share the correct pre-edit landscape snapshot for undo. Excavation deduplicates bank sampling and stops at existing cave voids.
- Starter-valley readiness calls the inherited checkpoint/player initialization before seeding new-world content.
- The candidate APK workflow sets the isolated package identity regardless of the current export preset's package name.

## Desktop measurements

These are instrumented Windows/headless measurements, **not Thor frame-rate evidence**. Host load varied between runs.

| Probe | Before | After |
| --- | --- | --- |
| Sparse diagonal stroke, two edit-list consumers | 2,191,328 voxel reads; 1,742 ms | 0 history-buffer reads; 0.027–0.040 ms |
| 20 m stream, 5 m width, 81 points | 22,975 ms | 272 ms; exactly the same 7,664 cells |
| Local meadow terrain edit | 82,832 voxel reads for full refresh | 255 reads; mesh matches a fresh build exactly |
| Native 2 m water commit, 0.75 m brush | 2,504–4,096 ms during investigation | 177 ms after local refresh and native column queries |

The full native commit includes authoritative terrain writes and synchronous scene callbacks. Large commits and GPU mesh uploads can still cost more than one frame; these measurements do not establish a device frame-time bound.

## Verification

Pinned runtime: Godot `4.7.2.stable.official.ed1daf0bf`; native voxel extension from `dependencies.lock.json`.

Targeted checks cover sparse edit cells and memory accounting; native water commit/undo/redo/cancel with exact terrain byte hashes; cave-safe excavation; stream raster equivalence and preview parity; multi-frame water mesh indices and local invalidation; meadow exact mesh equivalence; and house landing reconciliation.

Local receipts are under `reports/logs/iteration-terrain-water-*`, `iteration-water-local-refresh-2`, and `iteration-water-commit-profile`. Temporary baseline probes are ignored and are not shipped. Existing sculpt, backend, scaled-world residency, painted-path/history/excavation, water geometry/carve/visual/surface, and waterfall suites passed during iteration. New terrain and water regressions are registered in the explicit CI test lists.

The native residency test now asserts full-world diagonal coverage instead of the obsolete exact 64 m viewer distance. A missing mock signal guard found during the meadow check was corrected and its suite rerun successfully.

ARM64 packaging and signature/native-library verification run against the pushed commit through the existing delivery workflow. The final delivery includes its matching APK verification receipt. Physical Thor controller/performance testing and visual approval have not been run in this session.
