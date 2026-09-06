# M1 implementation and integration plan

The player authorizes both `tasks/M1-editable-cottage.md` and `tasks/M1-terrain-sculpting.md`. Their acceptance checks are cumulative. A modest visual checkpoint surrounds the same editable cottage. No M2, villagers, catalogue, full valley, bridge system or day/night cycle.

## Preserve the baseline

Retain the M0 scene, native volumetric backend, optional geometric stamping and its subtle exact-volume preview, checkpoint recovery, controller safety and regression suite. Existing M0 saves remain available. Continuous sculpting becomes the M1 terrain default; it uses hold/release and a restrained influence preview instead of lock/confirm. Building transformations remain cancellable discrete previews.

Keep Godot 4.7.2.stable.official.ed1daf0bf, matching official templates, Voxel Tools GDExtension v1.7x at 75d3c6d996ed2331c80edcd8c3ebc947afc0f041, and development-only Godot AI 3.2.5. No dependency or permission change is proposed. Codex 0.153.1 and the existing gpt-5.6-luna/high worker configuration were rechecked; the earlier read-only delegation gate passed. Independent runtime model metadata was not exposed.

## Work ownership and sequence

The main Astra session now directly owns visual design, implementation, tests, render inspection and revision. The player's M1 visual rejection supersedes the previous mandatory Luna coding policy. Existing Luna work is preserved as the functional baseline; it is not visual approval. No Luna agent is being renamed or substituted for Astra.

Rebuild the disposable cottage and garden presentation around the existing building records and native terrain. Verify actual Mobile gameplay and close-up renders, then revise the largest gaps. Include an edited/resized cottage and clean captures. Preserve every existing M0/M1 regression and distinguish desktop results, physical Thor checks and the player's visual approval.

## Data and representation decisions

Authoritative building records are independent of derived meshes. Deterministic procedural details keep stable semantic identities; resizing never replaces manual intent with fresh defaults. Invalid anchors are visible and recoverable. A stale derived result may apply only to its current entity revision. Duplication allocates new identities and deep-copies the design.

Undo restores the complete building design records. Revision and ID-allocation counters remain monotonic bookkeeping so a later command cannot reuse an identity or accept stale derived work; tests compare every design record while excluding those counters.

The current native terrain uses a 16-bit TYPE channel and blocky meshing. Native grow/smooth helpers are SDF-only in the pinned source. Retain TYPE saves and native meshing; integrate fractional time/strength/falloff locally before committing discrete cell transitions. This is an application brush operation, not a replacement voxel engine. Accumulate first-touch originals for the stroke, not full-world snapshots each frame. Final algorithm and limits must be tested before claiming the sculpting requirements met.

Extend the existing complete-generation checkpoint publication to include the bounded cottage document in the same published generation as terrain. Validate both before publication and during recovery. Preserve the old M0 reader and data; use a separate M1 checkpoint root and test cold restart and corrupt/interrupted newest-generation fallback. Do not introduce a second independently published building save that could disagree with terrain.

Terrain and building revisions count their respective edits independently; equal numeric revisions are not required. Consistency means one synchronous snapshot of both current authoritative states, verified and published by one generation manifest. The M1 reader must reject terrain-only generations, while the M0 reader retains its legacy compatibility.

For the bounded visual experiment, use 96 × 64 × 96 native cells at 0.5 world units per cell, retaining the same 48 × 32 × 48 world-unit footprint. This doubles terrain resolution on every axis without expanding the world. M0 retains its original 48 × 32 × 48 grid and scale, scene and checkpoint root. M1's combined checkpoint validates the larger dimensions explicitly. Sculpt APIs use world coordinates; native buffer indices use cell coordinates. Fine building/vegetation geometry has its own smaller step size. This is a candidate for visual and performance review, not a final terrain-grid decision. Physical Thor measurements and player visual review remain required before locking it.

## Integration checks

Run the unchanged M0 regressions plus the full M1 building and sculpting scenarios. Exercise actual controller events through selection, handle previews, detail operations/recovery, brush settings/planes, cancel/commit, menus and focus/disconnect safety. Save and load complete generations in separate processes. Check rendered meshes against records and reject a deliberately stale derived result. Capture actual gameplay at normal and close camera distances.

Export native ARM64 builds early after integration and verify dependency inclusion, renderer metadata, signatures and development-tool exclusions. Run desktop renderer smoke/performance checks separately, with no competing Godot jobs. Record commands, counts, failures, versions and artifacts in the milestone report.

M0 is still not complete: its detailed Thor evidence and documented MCP script-persistence failure remain open. No authorized Android device was connected at this environment check. M1 physical controller comfort, sculpting/render costs and visual approval remain **not run** until tested by the player. Stop at the M1 handoff; no later milestone is authorized.
