# M2-03 — Home detail vocabulary and live editing UI

**Status:** implemented on `feat/m2-hamlet-building`; physical Thor feel and player visual approval remain separate.

## Scope

- Give every residential recipe a distinct default window and entrance family.
- Expose categorized window and door variations on every compatible selected detail.
- Add controller-first placement of additional windows and doors using the existing wall-locked, transactional attachment workflow.
- Make the woodland lodge read as stacked logs and the tall village home read as Tudor framing without changing structural scale or save authority.
- Keep colour and variation previews live while docking the picker away from the edited detail.
- Replace approximate screen rectangles with amber mesh-silhouette highlighting for detail editing and whole-house targeting from terrain mode.

## Acceptance

- Window/door browsing is preview-only; A creates one recipe revision and B restores the exact prior presentation.
- Added windows and doors create real wall openings, avoid other manual details, remain independently editable, and survive undo/redo plus save/reload.
- The expanded home menu remains above the controller prompt bar at 1280×720.
- Actual Mobile captures show the selected window, selected door, and terrain-hovered house unobstructed and outlined on their rendered geometry.

