# Hearthvale - packed-earth worn-ground first pass

2026-09-12. Branch: `fix/m2-packed-earth-worn-ground`.
Read `AGENTS.md`, `tasks/M2-hamlet-building.md`, and the current player request.
Previous handoff is preserved at `reports/handoffs/HANDOFF-8e384a13.md`.

## Starting point and scope

Exact parent: `8e384a13bc2fdbb4775f48bcb5917beb4db7076b`
(`fix/m2-packed-earth-quiet`), one commit ahead of the current
`feat/m2-path-ground-polish` head. No master merge or existing-branch rewrite.
The player approved starting the proposed packed-earth repair.

This first pass changes only the disposable packed-earth helper and its tests:

- Three readable, muted soil colours replace almost invisible blended wear.
  Linear-field clipping partitions grounded triangles into disjoint base,
  compacted and scuffed regions. The boundaries have real vertices; colours
  do not interpolate over the entire path. There are no raised overlays,
  additional materials or draw passes.
- Interior cross-section samples resolve off-centre patches. Small seeded,
  side-independent edge incursions break long parallel runs without per-cell
  noise. The existing safety envelope and minimum visible core are retained.
- Endpoint weighting now references the actual rendered boundary at 0.64,
  not the unused outer envelope at 1.0. Ends narrow more deliberately while
  keeping the saved centreline endpoint exact. Grass follows the new edge.

Native height sampling/coalescing, 0.004 top offset, existing grass limits,
material settings, saved paths, terrain authority, controller editing and both
stone renderers are unchanged. No dependency, engine, save or workflow change.

## Tests and evidence

The existing paths gate calls new `m2_packed_earth_contour_checks.gd` checks:
857 threshold/partition cases, flat-colour emission and winding, area coverage,
geometry bounds, readable palette, dominant base soil and actual endpoint
widths at 0.25/0.75/3.0. Existing authority, lifecycle, native grounding, geometry,
draw-count, stone-identity and performance gates are retained, not relaxed.

Matched Mobile captures now compare with the exact starting 8e384a13 helper,
retained verbatim as a test-only fixture with SHA256
`dd463b622e654c7049530be2e2bf68313b26e8b074d01053161916c3eeb5cf36`.
The previous fixtures remain available. Cameras and capture scene are unchanged.

Local: exact original script/test blob hashes verified. An independent Python
geometry reference passed 857 partition/overlap cases (maximum area error
1.11e-16; maximum five triangles per input triangle). This is a mathematical
cross-check, NOT execution of the GDScript or native game. Godot is unavailable
in this editing container; native/render/export checks were not run locally.

The unchanged push-triggered verified Drive workflow is required on this exact
commit before calling it delivered. Check its paths shard, Mobile captures,
performance and verified ARM64/Windows packages; do not reuse a baseline pass.
No new CI result or APK is claimed by this source-time handoff.

## Remaining work / review

This is the contour/soil/taper slice, not completion of the whole proposal.
Gentler bend geometry, network footprint union, junctions and context-aware
threshold/bridge contacts are not implemented here. The endpoint taper is not
yet doorway-aware. Inspect the matched close/reverse/terrace captures before
further tuning; do not call the visual result accepted without player review.
Hosted Mobile evidence is not physical Thor evidence.

Execution: repository preference is Sol/high. This session exposes GPT-6 Astra
Pro; no delegation or claimed model switch was performed.
