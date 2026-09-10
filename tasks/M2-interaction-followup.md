# M2 interaction follow-up — Thor feedback, 2026-09-10

The player tested APK 9f7d0eb1: the opaque shader looks good and play is good. This is qualitative player approval, not a numerical frame-time measurement. Interaction repairs take priority over further visual polish; the lighting study stays separate and inactive.

## Personal decoration colour — implementation in draft PR #6

Individual explicit colours override the house accent, which is only a default. Preserve live preview, apply/cancel, undo/redo, generated custom-window joinery, unselected homes, duplication and reload. Explicit Natural wood is different from an absent/inherited colour. Do not introduce a new save schema or change the accepted shader.

The initial native CI run 34531174042 passed 310 of 315 new colour checks. Five later checks found missing geometry, not an incorrect material colour: the test restyled a stale automatic centre-window selection after a manually placed flower box had displaced it. Locking that window intentionally made the box need placement. The follow-up selects a currently visible, unpainted window after fixture construction. All existing colour/material assertions remain; runtime confirmation of that fixture correction is pending. Do not label this repair delivered until its gated build is verified.

## Minimal object-anchored colour picker — latest player sketch

The player's supplied sketch supersedes the earlier suggestion of a title, named swatches and explanatory text. Show only a small floating row of colour choices beside the selected object, with a pointer/anchor linking it to that object and the existing controller prompt strip. No visible heading, colour-name list, duplicate instructions, or large background panel. Retain a clear non-colour-only focus indicator and accessible names without displaying an instruction sheet.

Keep the selected object visible while previewing. Clamp/reposition the popup near screen edges and above controller prompts; do not cover its target when another placement fits. Controller left/right browses, confirm applies, cancel restores; menus continue to block world editing. Preview must not alter saved data or create undo entries.

Status: accepted interaction specification; floating picker **not implemented by the colour-precedence patch or its fixture correction**.

## Existing upper-floor and section editing

The player approved: select an existing floor/section, highlight that exact section and resize it in place after placement. Provide a discoverable controller route and in-world feedback rather than asking the player to add another portion. Preserve section IDs, floor support, windows and attachment recovery, read-only preview/cancel and one undo transaction. Include reverse-camera views, stacked and joined buildings, stale-edit rejection, duplication and save/reload.

Status: **not yet implemented**.

## Direct roof and wall editing — new player request

Point at/select the roof in the world, then expose its shape and material controls in a compact contextual picker at the target. Likewise, selecting walls should expose the relevant wall editing/material controls without detouring through the large X / Home options menu. Keep whole-house operations such as moving and duplicating the building distinct from editing one of its parts. Shape choices should be readable silhouettes and materials should be visual choices; do not replace one text-heavy menu with another.

Current implementation inspected at 7fb877b: roof profile and wall/roof material setters are house-wide. Direct targeting and the scope of an edit must agree. Before implementing per-wall material authority, settle whether a wall selection edits just that wall or the home's complete wall finish; never silently repaint unrelated walls while only one wall is highlighted. The existing joined-roof profile similarly affects the combined roof, and its highlight must make that scope honest. Local-scope data must retain stable identities and regenerate through the normal saved-record pipeline rather than ad hoc material changes.

Status: requested UX scope recorded; direct roof/wall pickers **not yet implemented**.

## Evidence and delivery

No local Godot executable is installed; an actual GitHub-host network probe in this session fails DNS, so local engine tests are not claimed. Use the existing pinned native CI, real Mobile captures and verified ARM64 export/private Drive workflow. The player permits continuing independent work without waiting for APK export; an unverified package is not delivered. No subagents or model switch are used; exposed model is GPT-6 Astra Pro rather than the repository's preferred Sol. Keep source changes small and the PR draft until checks succeed. Physical Thor/controller feel and visual approval remain the player's checkpoints.
