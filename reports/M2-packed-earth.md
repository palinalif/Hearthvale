# M2 packed earth — worn-ground refinement

## Reference

Branch: `feat/m2-path-ground-polish`.
Exact before commit: `e8560f30e2466854ab359459463659e0c9cd5b9e`.
Baseline delivery: GitHub Actions run `34669385153`, successful.
Baseline source and actual-Mobile paths artifacts were downloaded and inspected.
No older baseline or unrelated master changes are used.

## Implementation

Only the packed-earth dispatcher/preview changes. The old box/shoulder/patch
implementation is bypassed, not covered with another decorative layer.
A dedicated render-only helper constructs connected route stations and a
continuous top surface. Independent slowly varying edges use stable path ID
and cumulative route distance. Extents stay inside nominal half-width and
retain at least 94% of the requested width. End corners retreat slightly
rather than forming conspicuous square slabs. The centreline and records
are unchanged.

Each surface polygon is clipped to coalesced equal-height native terrain
rectangles. Every triangle sits 0.004 world units above its own native top.
There is no slab body, tall exposed side, interpolated terrain flattening,
terrain mutation, cutout or mask. Equal-height cells coalesce before emitting
geometry. Adjacent stations share boundary positions rather than overlapping
independent boxes. Soil uses one low-contrast continuous vertex-colour field
based on the existing earthy palette; rectangular dark patches and rails are
not emitted. Normal clockwise culling remains enabled.

Grass reuses the accepted contact seed, 0.0625 cubic detail language, existing
vegetation palette, box batching and local terrain-height interface without
modifying the accepted contact helper. Groups occur on one selected side,
not paired borders, with unequal bare intervals. Whole cells avoid the central
60% of the walking width. Footprint corners must agree with each root's local
native height. Each group is two adjacent columns, 3–4 cubes total and no more
than 0.1875 high. At most 8 groups/path and 64 total are emitted, canonically
ordered by stable path ID. Grass uses the former second dirt surface; no node
or material per group, no additional opaque surface draw and no grass shadow
pass. Rebuild-local height caches expire with the generated batch.

No changes to terrain/save authority, path editing semantics, section placement,
refresh triggers, dependency pins, export settings or CI gates. Existing scene
revision/preview caching and cleanup drive regeneration. The old locked
`_append_path` body and shared helpers are retained verbatim, even though its
packed-earth arm is no longer called in production, so no accepted source-lock
assertion is weakened. Cobblestone, stepping stones and stone contact remain
byte-identical; the new native gate compares actual mesh arrays to the baseline.

## Evidence and checks

`tests/m2_packed_earth_checks.gd` extends the existing Roads & Paths gate.
It checks repeat generation, JSON reload/reordered records, cleanup/restoration,
preview cancel, terrain dig/cancel/release/undo, unchanged documents, finite
lateral bounds, per-triangle clockwise winding and native-height agreement,
width continuity at 0.25/0.75/3.0, the existing box-equivalent geometry ceiling,
at most two dirt surfaces and the unchanged seven-surface total opaque ceiling.
All original stepping-stone winding/contact/dig assertions are retained.

Before captures compile the exact baseline renderer text, normalized-LF SHA256
`1ff5bcb9841fc25d6a2566ecdb43a974afc66d2d75f6428df48792e38ee03713`
checked before removing only its duplicate global-class declaration. It consumes
the same runtime native terrain, authoritative path records, materials and
lighting as the candidate, using identical cameras. No substitute ground or
special raised review geometry is used. The fixture is test-only and excluded
by existing package rules.

Matched output under `reports/screenshots/m2-paths/` and `before/`:
`all-styles.png`, `stepping-close.png`, `stepping-reverse.png`,
`packed-earth-close.png`, `packed-earth-reverse.png`, and
`packed-earth-terrace.png`. The close view includes the existing broad bend.
The terrace pair adds one identical normal path record to both renderers on
unmodified native terraces, then restores the full saved document.

Local verification before push: 17 existing source locks match; 10 existing
Python delivery/performance-contract tests pass. Native/GDScript/Mobile tests
are not available locally; the unchanged verified Drive workflow is the
required execution and delivery gate for the new commit. Do not treat the
baseline's green status as a candidate pass. Exact candidate counts, measured
cost and package/Drive receipts belong to its CI run and final task report.
Actual Mobile on a hosted Windows renderer is not a physical Thor benchmark.
Player visual approval remains the final acceptance decision.
