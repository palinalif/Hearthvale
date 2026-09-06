# M1 implementation and integration plan

The player authorizes both `tasks/M1-editable-cottage.md` and `tasks/M1-terrain-sculpting.md`. Their acceptance checks are cumulative. A modest visual checkpoint surrounds the same editable cottage. No M2, villagers, catalogue, full valley, bridge system or day/night cycle.

## Preserve the baseline

Retain the M0 scene, native volumetric backend, optional geometric stamping and its subtle exact-volume preview, checkpoint recovery, controller safety and regression suite. Existing M0 saves remain available. Continuous sculpting becomes the M1 terrain default; it uses hold/release and a restrained influence preview instead of lock/confirm. Building transformations remain cancellable discrete previews.

Keep Godot 4.7.2.stable.official.ed1daf0bf, matching official templates, Voxel Tools GDExtension v1.7x at 75d3c6d996ed2331c80edcd8c3ebc947afc0f041, and development-only Godot AI 3.2.5. No dependency or permission change is proposed. Codex 0.153.1 and the existing gpt-5.6-luna/high worker configuration were rechecked; the earlier read-only delegation gate passed. Independent runtime model metadata was not exposed.

## Work ownership and sequence

The lead owns this plan, architecture, shared project/export configuration, integration and final review. Two existing Luna workers handle coding and tests in separate files:

1. Building data: `building_world.gd` and its tests. Stable identities and anchors, automatic records plus overrides/exclusions/manual additions, bounded transactional history, strict document validation, duplicate independence, recoverable unsupported details and monotonic mesh revision guards.
2. Terrain strokes: `terrain_backend.gd`, a bounded sculpt helper and their tests. Time-based local native updates, advancing surfaces, connected movement, fixed height/slope references, smooth, exact whole-stroke history and cancellation. Preserve existing stamp APIs and tests.

After these interfaces settle, assign controller/rendering and consistent checkpoint integration to the same workers with non-overlapping ownership. No more than two coding workers operate concurrently. Shared editor/MCP mutations remain with the lead. Worker reports do not establish acceptance; the lead independently runs tests and inspects changes and rendered output.

## Data and representation decisions

Authoritative building records are independent of derived meshes. Deterministic procedural details keep stable semantic identities; resizing never replaces manual intent with fresh defaults. Invalid anchors are visible and recoverable. A stale derived result may apply only to its current entity revision. Duplication allocates new identities and deep-copies the design.

The current native terrain uses a 16-bit TYPE channel and blocky meshing. Native grow/smooth helpers are SDF-only in the pinned source. Retain TYPE saves and native meshing; integrate fractional time/strength/falloff locally before committing discrete cell transitions. This is an application brush operation, not a replacement voxel engine. Accumulate first-touch originals for the stroke, not full-world snapshots each frame. Final algorithm and limits must be tested before claiming the sculpting requirements met.

Extend the existing complete-generation checkpoint publication to include the bounded cottage document in the same published generation as terrain. Validate both before publication and during recovery. Preserve the old M0 reader and data; use a separate M1 checkpoint root and test cold restart and corrupt/interrupted newest-generation fallback. Do not introduce a second independently published building save that could disagree with terrain.

For the bounded visual experiment, retain the native patch dimensions and test a smaller physical terrain scale around a proportionate cottage. Fine building/vegetation geometry has its own smaller step size. This is a candidate for visual and performance review, not a final terrain-grid decision. Physical Thor measurements and player visual review remain required before locking it.

## Integration checks

Run the unchanged M0 regressions plus the full M1 building and sculpting scenarios. Exercise actual controller events through selection, handle previews, detail operations/recovery, brush settings/planes, cancel/commit, menus and focus/disconnect safety. Save and load complete generations in separate processes. Check rendered meshes against records and reject a deliberately stale derived result. Capture actual gameplay at normal and close camera distances.

Export native ARM64 builds early after integration and verify dependency inclusion, renderer metadata, signatures and development-tool exclusions. Run desktop renderer smoke/performance checks separately, with no competing Godot jobs. Record commands, counts, failures, versions and artifacts in the milestone report.

M0 is still not complete: its detailed Thor evidence and documented MCP script-persistence failure remain open. No authorized Android device was connected at this environment check. M1 physical controller comfort, sculpting/render costs and visual approval remain **not run** until tested by the player. Stop at the M1 handoff; no later milestone is authorized.
