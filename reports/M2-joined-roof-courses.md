# Roof finish 02 — joined and upper-floor surface skin

2026-09-11. Player requests continuing while they playtest roof build 5387de89 after breakfast. This candidate branches from that exact source; PR #11 and its APK remain unchanged. No merge or aesthetic approval is inferred.

## Bounded change

Generate genuine stepped tile surfaces for joined L/T/U roofs and exposed upper/lower roof areas, using the existing union roof heights and gradients. Detail-cell columns retain the occupied footprint, half-bond joints recess one decorative cell while preserving backing, and greedy meshing emits only exposed faces in three material draws. This replaces overlapping smooth boxes with grid-aligned surface geometry without filling courtyards or introducing a cube node per cell. No new roof-profile algorithm, height map terrain replacement, or shader is involved.

Keep the original joined eave/edge treatment, wall/foundation geometry, roof-accessory anchors, skylines at the same source pitch, and all personal material choices. Fine quantization can move the surface by a decorative cell; the saved roof shape and dimensions are not resized. Non-tile materials, single-section gables and custom hip/saltbox/gambrel/shed roofs retain their preceding paths. Facade/foundation relief is still the next separate slice, not implemented here. Lighting and the unmerged bottom-half catalogue remain separate.

Cache the new generated skin on its nodes. Repeated presentation does not rebuild it. Material/shape/section changes invalidate through the existing shell rebuild. Selection must use exact solid runs, never one combined mesh AABB that bridges the U courtyard. All three draws still participate in surface and whole-house highlighting. Oversized or unsupported tessellation falls back to the preceding roof path before allocating its fine columns; no detail cells are stretched.

## Validation added

- Independent small solid-voxel oracle verifies every emitted face once, with holes, steps, disconnected heights and negative coordinates; actual mesh normals/winding and decorative-grid vertices are checked.
- L/T/U footprints, three presentation scales, partial upper floors, nonempty seam backing, immutable recipes, deterministic regeneration and complete solid picking runs.
- At the handheld scale, surface triangles must not exceed the original roof-box triangle count. Independent Python arithmetic on representative layouts suggested a reduction, but these estimates are not native-engine or device performance results.
- Actual Mobile normal/close/reverse U and genuinely resized upper-floor before/after comparisons, eight screenshots. Fixed lighting, framing and wind; unchanged building/landscape records; no-retessellation/pixel-stability checks; edited save/reload geometry parity and empty-courtyard pick tests.
- The new native and Mobile checks are added to the unchanged full delivery gate. Original roof-course, house-editing, window/shutter, save and package checks remain.

At commit preparation: verified source-archive SHA-256 f6392c75e2753a1e7b11cd24d924f74c8c1ba70cc886bb602aef34bc3b64399e, narrow source review and independent Python layout counts. No local Godot executable is installed; an actual git remote probe failed DNS. Native CI, Mobile appearance, APK verification and physical Thor testing are pending. Do not deliver the new APK or claim this looks better without the corresponding evidence. The exposed lead is GPT-6 Astra Pro rather than repository-preferred Sol; no model switch or subagents were used.
