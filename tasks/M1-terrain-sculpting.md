# M1 — continuous volumetric terrain sculpting

**Status:** explicitly authorized alongside [the editable cottage](M1-editable-cottage.md). Both tickets are required; neither replaces the other. M0 evidence gaps remain open.

## Interaction and visual intent

Planet Coaster / Planet Zoo guide sculpting interaction. Town to City and Station to Station remain the detailed voxel-miniature visual references. Preserve native volumetric terrain, including caves and overhangs. No heightmap substitution or custom voxel engine.

Holding the sculpt action gradually changes terrain; moving while holding produces a connected stroke. Holding still continues building or excavating. Release commits one undo transaction without a second confirmation. Geometric stamping may remain optional, but is not the default. Size controls influence area, strength controls rate, and falloff controls centre-to-edge influence. Provide gentle defaults and controller adjustments.

## Required tools

- **Raise/add:** gradual growth with soft falloff; brief input makes a small change and longer input builds further, without repeated obvious spherical lumps.
- **Lower/dig:** gradual excavation into ground, slopes and walls, retaining caves and overhangs.
- **Flatten to height:** capture the world height of the terrain hit at the cursor centre when the stroke begins. Keep that horizontal target fixed throughout the stroke; raise low terrain and lower high terrain toward it without overshoot. Provide an explicit keep-target toggle and resample action. Show the reference plane/height. Height snapping is optional and off unless selected.
- **Flatten to surface:** capture a meaningful local surface plane from neighbouring geometry, rather than one axis-aligned voxel face. Keep its position and slope fixed throughout the stroke to extend an incline.
- **Smooth:** gradually modify local geometry to soften abrupt transitions. Preserve the stepped art style; no global smoothing or shading-only substitute.

## Controller feel and safety

Retain the revised controller layout and camera controls. All tool choice, size/strength/falloff adjustment, precision, plane sampling and keep-target controls must work without mouse, touch or keyboard. Show mode, a restrained influence footprint, settings and locked plane without obscuring the work. The footprint is an area of influence, not an exact instant geometric cut. Keep the optional stamp tool's ghost volume and precise affected-voxel highlight separate from this meaning.

One press-to-release stroke is one exact undo operation. Cancel restores the pre-stroke terrain. Menus block sculpting. Pause, disconnect and focus loss safely end editing and require a fresh press before resuming. No held brush may restart automatically. Targeting stays stable as terrain changes: excavation must not jump to distant geometry behind it, and flatten targets must not drift.

## Implementation constraints

Inspect the current representation before choosing the algorithm. Explain necessary format changes and preserve existing saves or provide an explicit migration. Strength is time-based, not frame-based. Interpolate moving influence so updates do not leave isolated stamps. Keep native updates and accumulated undo data local; no full-world rebuild or full-world snapshot per brush update. Preserve consistent checkpoint publication.

## Acceptance evidence

- Held input progressively builds a hill and excavates a hollow.
- A dragged stroke makes connected, controllable changes.
- Horizontal flatten extends a pad at its original captured height, including across successive strokes with keep-target enabled.
- Surface flatten extends an incline and smooth blends its edges locally.
- Cave and overhang editing remains functional.
- Whole strokes cancel, undo, redo and survive save/restart exactly.
- Equivalent timed input at 30 and 60 fps produces approximately equivalent results; record the comparison and tolerance.
- Controller menus, focus loss, pause and disconnect prevent held-action leakage.
- Use the pad/riverbank around the same editable cottage as the integrated playtest scene; retain every cottage regression and acceptance check.

Report automated and rendered desktop evidence separately from physical Thor playtests. Unavailable device checks are **not run**. Neither visual screenshots nor unit tests establish comfortable controller use on the Thor.
