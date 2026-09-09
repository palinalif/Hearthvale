# M2 — Build a convincing hamlet

**Status:** active; implementation authorized by the player on 2026-09-09.

**Objective:** broaden the proven M1 cottage system into a small but expressive residential building vocabulary, and let the player freely compose those homes through a controller-first placement and rotation workflow before inhabitants or autonomous place simulation are introduced.

## Residential variety

Provide at least three materially different home configurations spanning multiple footprints or massing shapes and multiple coherent architectural styles. Variants must differ in form and architectural language rather than being palette swaps alone. Reuse the M1 authoritative-building, attachment-recovery, controller, save, undo, and regeneration contracts.

Allow wall and roof materials to be selected independently. Shape, style, wall material, and roof material are authoritative saved choices. Changing any of them must preserve compatible manual details; incompatible attachments remain visible and recoverable rather than being discarded.

## Free placement and rotation

Provide an explicit **Place home** route that opens the residential catalogue instead of requiring the player to duplicate the default cottage. Choosing a design enters an in-world placement preview and does not create authoritative world data until confirmed. A placed home receives an independent stable building identity and its own deep-copied design records.

Placement is free within the editable world rather than restricted to predetermined lots. The preview follows the world cursor while the camera remains usable. It shows the complete home ghost, footprint, front/facing indicator, foundation or terrain impact, and a clear valid/invalid state. When placement is blocked, show the specific reason in plain language—for example world bounds or a hard overlap—rather than merely changing colour. Reasonable slopes should be handled by the approved foundation response where possible instead of creating arbitrary placement restrictions.

Rotation supports quick predictable coarse steps and a controller precision mode for finer yaw adjustment; the exact default increments remain a physical playtest decision. Snapping can be toggled without making unsnapped placement inaccessible. The preview, collision footprint, attachment transforms, entrance facing, and prospective foundation update continuously and must always agree.

Selecting an existing home exposes **Move / rotate** using the same preview grammar. Its stable building and attachment identities, shape/style, materials, manual edits, and recoverable details remain intact. Moving or rotating a home must not be implemented as delete-and-recreate or as duplication of the default cottage.

## Placement UI and safety

- The home catalogue presents each available design with a readable silhouette, name, shape/style summary, and current wall/roof material choices. It clearly distinguishes **Place new home** from **Duplicate selected home**.
- Placement HUD prompts expose move, rotate, precision/snap, camera, confirm, and cancel through the established controller glyph system. Focus order and prompts update when the player changes between catalogue, placement, and ordinary editing.
- Validity cannot rely on colour alone. Use the ghost/outline, a status icon, and a short reason label while keeping the home and terrain readable.
- Confirm commits the home transform plus any approved foundation/planting effects as one undo transaction. Cancel restores the exact prior terrain, planting, selection, and building state.
- Menus block world input. Pause, focus loss, or controller disconnect safely suspends or cancels the preview and requires a fresh confirm press; reconnect must never place a home accidentally.
- Overlapping candidates can be inspected and cycled without losing the preview. The player can return to the catalogue without committing or discarding their current design choices.
- No zoning, economy, construction timer, or predetermined-lot requirement is introduced. Hard validation exists only for concrete world/data constraints and must be explained to the player.

## Hamlet composition

Support the paths, simple bridges, gardens, street furniture, vegetation placement, and composition tools needed to make several homes read as a coherent hamlet. This ticket does not authorize inhabitants, autonomous activities, or multi-storey generation; multi-storey generation remains a separately recorded unscheduled backlog idea.

## Acceptance outline

- The controller route can select each home configuration and independently change its shape/style, wall material, and roof material.
- Every configuration remains editable through the inherited M1 resize and detail tools.
- Compatible manual details survive configuration and material changes; incompatible details enter recoverable placement state.
- From the catalogue, the player can choose a design, preview it away from the default cottage, use coarse and precision rotation, understand validity without relying on colour, and place a new independent home.
- The player can move and rotate an existing edited home; confirm preserves its identity and edits, while cancel restores its exact prior state.
- Placement, relocation, rotation, foundation/planting effects, undo/redo, duplication, save/restart, stale-result rejection, and independent building identities pass across the residential set.
- Invalid overlap and bounds cases explain the reason and cannot commit; disconnect, pause, focus loss, or a stale confirm cannot accidentally place a home.
- From a cold launch without touch input, the player can compose several distinct homes into an attractive hamlet scene without using predetermined lots.
- Automated evidence, Mobile-render captures, Thor performance/controller review, and player visual approval are reported separately.

Implementation began from the accepted M1 baseline on `feat/m2-hamlet-building`. Deliver in bounded vertical slices; the first is controller-first placement and rotation using the existing cottage before expanding the residential catalogue.
