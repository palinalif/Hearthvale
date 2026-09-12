# Hearthvale — packed-earth refinement handoff

2026-09-12, branch `feat/m2-path-ground-polish`.
Read `AGENTS.md`, `tasks/M2-hamlet-building.md`, and the current user request.
The preceding handoff is preserved verbatim in
`reports/handoffs/HANDOFF-e8560f30.md`; its inherited contracts remain in force.

## Exact starting point and scope

Actual branch head resolved before editing and rechecked before commit:
`e8560f30e2466854ab359459463659e0c9cd5b9e`.
Its verified delivery run is `34669385153`.
No reset, master merge, terrain-authority, saved-record, section-placement,
cobblestone or stepping-stone change is included.

Packed earth now dispatches from `scripts/m2_path_visual.gd` to the disposable
`m2_packed_earth.gd` helper. The old packed-earth branch inside `_append_path`
is no longer called by the runtime/preview dispatcher. It is intentionally left
byte-identical because the accepted contact gate locks that entire method.
All 17 existing helper/constants source locks remain unchanged. Stone placement,
size variation, winding, separation, materials and contact are preserved.

The replacement is a top-only native-terrain skin, coherent distance-based
edges, quiet soil vertex colours, and capped small cubic edge grass in the
existing dirt batch. No terrain mask, saved decoration, extra draw pass or
per-frame generation is introduced. See `reports/M2-packed-earth.md`.

## Verification and delivery

Local source-lock comparison: 17/17. Existing Python delivery/performance
contract suite: 10 passed. Local Godot/native/Mobile execution is unavailable
in this editing container; it is NOT claimed as run.

The unchanged push-triggered verified Drive workflow must verify this exact
new head, including native checks, actual-Mobile paths/performance, Android
ARM64 and Windows package validation, before private Drive delivery. Do not
infer success from the baseline run. The new path gate records deterministic
geometry, bounded extents/cost, native height agreement, lifecycle/authority,
stone byte-identity and matched before/after images. Its artifact contains
`all-styles.png`, retained stepping close/reverse, packed-earth close/reverse,
and an additional native terrace crossing; matched originals are in `before/`.
`PACKED_EARTH_AUDIT` and `PACKED_EARTH_BEFORE_COST` in the paths log report cost.
Use the exact-head CI receipts and final task report for completed results.

Hosted Windows D3D12 Mobile-renderer evidence is not physical AYN Thor testing.
Physical Thor testing and player visual acceptance remain separate. Stop at
packed earth; no cobblestone, junction or further stone redesign is authorized.

Execution note: repository preference is Sol/high for visual work; this session
exposes GPT-6 Astra Pro rather than that requested runtime. No delegation or
silent model substitution was performed.
