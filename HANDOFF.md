# Hearthvale - packed-earth surface pass (work in progress)

2026-09-12. Branch: `fix/m2-packed-earth-worn-surface`.
Base: `fix/m2-packed-earth-quiet` at `8e384a13bc2fdbb4775f48bcb5917beb4db7076b`.
The preceding handoff is preserved in `reports/handoffs/HANDOFF-8e384a13.md`.
Read `AGENTS.md`, the current user request and `tasks/M2-hamlet-building.md`.

The user authorized implementing the proposed packed-earth repair. This first
commit tackles the soil surface, small boundary incursions and asymmetric end
taper. It is NOT a finished/visually accepted delivery. Junction unions,
doorstep-aware termination and fitted curve transitions remain future steps
of the proposed repair; the authored route is deliberately not moved here.

Three explicit soil colours replace nearly invisible vertex washes. Each
native-grounded triangle is partitioned into adjacent base/compacted/scuffed
regions, with vertices at wear boundaries and no overlapping decal layer.
Presentation samples resolve at 0.25 units; small coherent edge bites retain
the existing 0.0625 lateral-detail vocabulary and safety envelope. End taper
uses physical distance instead of a fixed station count.

Terrain clipping, height lookup, materials/batching, grass helper bodies,
saved records, stone styles and the shared renderer are unchanged. Existing
geometry/draw/lifecycle/authority assertions remain intact. New surface tests
run from the existing packed-earth width gate. Matched Mobile cameras now
compare against an exact, SHA256-checked copy of the actual 8e384a13 helper.

Local numerical/source checks PASS: 10,000 complementary clipping partitions;
0.25/0.75/3.0 width bounds and existing scalar wear assertions; eight unchanged
renderer helper bodies; unchanged native-height/lifecycle/camera test bodies.
These are NOT native Godot results. This container has no Godot runtime and
could not clone over its network; source was read/written through GitHub and
all three edited/new GDScript blobs matched the locally checked bytes.

Required before delivery/merge: exact-head native regression, actual Mobile
before/after review, geometry/performance gates, verified ARM64 APK/Windows
packages and the existing gated private Drive delivery. Keep the PR draft
until that evidence exists. Physical Thor testing and visual approval belong
to the user. Do not reuse the base run as evidence for this commit.

Execution: GPT-6 Astra Pro is exposed, not the repository's preferred Sol/high.
No delegation or runtime substitution was performed.
