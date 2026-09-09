# M2-01 — Placement and rotation foundation

**Status:** Active

Prove the M2 transform and safety path using the existing cottage before adding more home recipes or catalogue art.

## Scope

- Rotate a new-home preview with coarse controller steps and a precision mode.
- Allow rotation snapping to be toggled while keeping fine unsnapped adjustment accessible.
- Preview and atomically commit translation plus yaw without mutating authority beforehand.
- Move and rotate an existing edited home without changing its stable identity or authored details.
- Explain world-bounds and hard-overlap failures in text and block their confirmation.
- Reject stale confirmation after the source recipe changes.
- Preserve cancellation, undo/redo, duplication, save/reload, camera control and the accepted M1 interaction grammar.

## Acceptance

- D-pad left/right rotates the complete preview; D-pad up toggles snap and L3 toggles precision.
- The rendered ghost, committed transform and saved transform agree.
- Invalid bounds and overlap states name their reason and cannot create or move a building.
- A valid duplicate is one transaction with fresh deep-copied identities.
- A valid move/rotation is one transaction retaining the existing building and attachment identities.
- Cancel and stale input leave the complete authoritative document unchanged.
- Focused M2 checks and inherited M1 placement/house-action regressions pass.
