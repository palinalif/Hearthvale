# M1 — one cottage that does not eat your edits

**Status:** implementation authorized by the player's scope correction; unresolved M0 evidence remains open and must be reported separately.
**Objective:** prove the core interaction and non-destructive generation model before adding content.

**Parallel required workstream:** [M1 continuous terrain sculpting](M1-terrain-sculpting.md), explicitly added by the player. It supports the same cottage pad/riverbank and does not replace or reduce any building requirement below. Continuous sculpting uses hold/release; lock/confirm remains appropriate for optional geometric stamping and discrete building previews.

**Authority:** this is the authoritative M1 ticket. The main deliverable is one stretchable procedural cottage, including editable generated details and persistent manual choices. Disregard any postcard-only/no-procedural-building interpretation. A static cottage or screenshot cannot satisfy this ticket. Duplication tests may create another instance of this same cottage; they do not authorize a building catalogue.

Read sections 3 and 5 of `../docs/design.md` and `../docs/references/README.md`. Keep the scope to one rectangular building volume, one gabled roof profile, a tiny detail set, one small terrain pad presented as a scenic riverbank, and controller-operated handles.

## Visual review before catalogue expansion

During M1, present a small cottage-and-riverbank scene to the player before expanding the building catalogue. Town to City guides architecture, street decoration, planting, and intimate village composition. Station to Station guides landscape palettes, vegetation, and the detailed voxel-miniature aesthetic. Tiny Glade remains the building-interaction reference; the original screenshots remain terrain/geography references.

This is a modest visual checkpoint supporting the editable cottage: a landscaped pad or riverbank, a few trees, considered materials and lighting. It does not replace the procedural-building deliverable or require a full valley, bridge system, day/night cycle, villagers, or expanded catalogue. Retain the latest controller feedback: precise, legible targets, restrained highlights/thin outlines, ghost previews, and reliable cancellation.

Show readable silhouettes, fine stepped details, coherent colours, inviting lighting, and restrained surface variation at normal controller camera distance and close inspection. The player found M0's terrain much too coarse: this scene must demonstrate substantially finer terrain forms and decorative detail. Oversized cubes, noisy textures, and photorealism do not meet the target.

Keep decorative geometry resolution independent of the terrain editing grid. Visible voxels need not be independently simulated blocks. Compare candidate detail scales in this bounded scene, retain native volumetric editing, and record Thor edit/render measurements before choosing a terrain cell size. A few plants and nearby decorative pieces support this review; no catalogue expansion, railway systems, economic management, or full river-editing system is added by this gate.

## Authoritative data

Persist a building ID, schema/generator versions, dimensions, transform, seed, style reference, stable surface IDs, and separate detail records. Represent automatic, modified/locked, suppressed, and manually added states explicitly. Do not identify a window by its current position in a generated array.

An anchor records its surface and positioning policy. Resizing can adjust the surface while preserving an attachment's intent. When no valid surface remains, keep the detail in a recoverable needs-placement state; this is not permission to drop it from the save.

Meshes are regenerated output. Keep the original record and its overrides available for undo, save, testing, and future asset replacement.

## Controller route

Select the cottage, select/cycle a handle, stretch one constrained axis, commit or cancel, choose a detail, move it in its surface plane, replace it, suppress it, and add a new attachment. Provide visible snap increments and a precision mode. Menus must block world edits.

## Required regression scenario

Create six automatic windows. Move one, replace one, suppress one, and add a flower box. Widen the cottage, shorten it, alter materials, undo and redo, save and reload, and duplicate it.

Valid edits persist. Suppressed details do not return. Orphaned details are recoverable. Undo restores the previous authoritative state, not just an approximate mesh. Duplication preserves the design while allocating independent entity/attachment identities; editing the copy must not change the source.

Repeat with shrinking past an attachment, deleting its supporting surface, cancelling a resize, and receiving a stale asynchronous mesh result. The latest valid record always wins.

## Done means

Automated data-level tests actually pass; the rendered cottage reflects those records; the save survives restart; and the player can complete the full interaction comfortably on the Thor with only a controller. Present the cottage-and-riverbank scene for visual review and record the player's feedback before catalogue expansion. Record screenshots and device feedback separately from unit-test output.

Do not expand into an arbitrary building boolean system, interior furnishing, numerous roof styles, or a large catalogue before this interaction is dependable and pleasant.

## Follow-up regression from physical feedback

The first M1 physical playtest found invisible raise/dig targeting, Dig apparently resizing the cottage, and an oversized cottage. Verify the real menu transition from Cottage to Terrain, select Raise and Dig, hold/release and move the stick, and assert that terrain changes while every building record stays unchanged. Terrain and Cottage menus expose only relevant actions; switching modes cancels a preview and requires a fresh action press.

Capture the target at normal/near/far zoom and behind an occluding cottage, with a restrained readable centre cue and influence footprint. A scene-tree visible flag alone is insufficient evidence. Show the smaller cottage within its surroundings; existing saved designs remain unchanged until an explicit undoable scale conversion. Verify transformed handles and full manual-choice/save/duplication preservation at miniature scale.
