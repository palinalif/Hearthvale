# Hearthvale feature backlog

This is the inbox for possible future features and explicit product boundaries. An entry here is **not authorization to design or implement it**, does not expand the active milestone, and does not override `AGENTS.md` or an authoritative ticket in `tasks/`.

## Lifecycle

`Idea` → `Candidate` → `Approved milestone` → authoritative `tasks/*.md` ticket → `Implemented`

- **Idea:** captured for later without a commitment or schedule.
- **Candidate:** planned enough to estimate, but still outside implementation scope. It must include the planning fields below.
- **Approved milestone:** explicitly assigned by the player; create an acceptance ticket in `tasks/` before implementation.
- **Implemented:** delivered and linked to its evidence in `reports/`.
- **Rejected:** intentionally outside the product vision; retain the entry so it is not repeatedly proposed.

Use the next `IDEA-NNN` identifier. Record the date, a short reason, important boundaries, and known dependencies. Keep implementation details in the eventual task ticket rather than expanding this file into a specification.

### Required candidate planning

When an idea is promoted to **Candidate**, add:

- **Implementation estimate:** a realistic range for active implementation time, followed by the important assumptions and exclusions. Also give a confidence level; do not present the range as a promise or silently include later device-review time.
- **Recommended model:** choose the primary implementer using this project mapping:
  - `Astra / low` for visual design and visually led implementation.
  - `Sol / medium` for difficult, coupled, or architecture-heavy coding.
  - `Luna / high` for easy, well-bounded coding tasks.
- **Model rationale:** one sentence explaining why the work fits that model. Split a feature into separately estimated/modelled workstreams when its visual and coding portions materially differ.
- **Acceptance outline:** a short description of what would demonstrate completion. The authoritative acceptance criteria still belong in the eventual `tasks/*.md` ticket.

Use this block beneath the idea description:

```md
**Implementation estimate:** 4–7 active hours
**Estimate assumptions:** Existing save schema and interaction patterns are reused; physical device review is separate.
**Estimate confidence:** Medium
**Recommended model:** Sol / medium
**Model rationale:** The feature touches coupled runtime and persistence code.
**Acceptance outline:** The feature works through the controller route, survives save/undo, and passes its targeted render and regression gates.
```

Conversational shorthand:

- `Idea: …` logs an idea without authorizing work.
- `Plan …` develops an idea into a candidate.
- `Approve … for M#` assigns it to a milestone and authorizes ticket writing.
- `Build …` begins implementation only when its milestone and ticket are active.

## Ideas

### IDEA-001 — Horses

**Status:** Idea  
**Priority:** Unscheduled  
**Added:** 2026-09-08

Mounted transportation and ambient farm horses may fit Hearthvale's pastoral setting. Horses are the furthest the transportation theme should go; this does not imply a larger world or authorize character, riding, navigation, or animation work.

**Known dependencies:** A justified traversal need, character/animal animation, and navigation appropriate to the active milestone.

### IDEA-003 — Vertical house expansion

**Status:** Idea  
**Priority:** Unscheduled  
**Added:** 2026-09-08

Dragging a house upward past defined height thresholds should adapt its generated structure by adding a second or third floor, making height a meaningful way to expand a building rather than merely stretching a single-storey shell. Thresholds, floor composition, roof movement, stair/interior assumptions, and the effect on existing details remain to be designed. This remains an unscheduled idea and is not part of planned M2.

**Known dependencies:** Stretchable-building architecture, floor-aware procedural generation, attachment/decoration recovery, and save/undo compatibility.

### IDEA-004 — Water physics

**Status:** Idea  
**Priority:** Unscheduled  
**Added:** 2026-09-08

Add simulated water behavior to the world, including fluid movement and interactions appropriate to Hearthvale's voxel terrain. The simulation scope, visual treatment, and performance budget remain undefined.

**Known dependencies:** A defined water model, terrain integration, persistence, controller interaction, and a mobile-safe performance budget.

### IDEA-005 — Seasonal world changes

**Status:** Idea  
**Priority:** Unscheduled  
**Added:** 2026-09-08

Add changing seasons with seasonal variants for the affected world items and corresponding changes in people's behavior. The season cycle, transition rules, variant coverage, and behavior model remain to be designed.

**Known dependencies:** Villager simulation, seasonal asset pipeline and variants, world-state persistence, lighting/environment presentation, and behavior scheduling.

### IDEA-006 — Paintable recessed roads and pathing

**Status:** Idea  
**Priority:** Unscheduled  
**Added:** 2026-09-08

Allow players to paint roads and paths from a broad texture palette. Road surfaces should be slightly recessed so materials such as cobblestone can read as proper paths; painted roads would later influence villager pathing. Town to City is a reference for the intended path composition and variety.

**Known dependencies:** Terrain editing and material representation, a large authored texture/road set, recessed path geometry, villager navigation/pathing, and save/undo compatibility.

### IDEA-007 — Free building placement and rotation

**Status:** Approved milestone — M2
**Priority:** M2
**Added:** 2026-09-09

Allow the player to choose a home design, preview it, rotate it freely, and place a new independent building at a valid location instead of creating new buildings only by copying the default cottage. Existing homes can also be moved and rotated without losing their identities or edits. Placement is controller-first, cancellable, undoable, and compatible with terrain, foundations, saves, and stable building identities. Detailed UI, UX, safety, and acceptance requirements are authoritative in `tasks/M2-hamlet-building.md`.

**Known dependencies:** Multiple home recipes, placement validation and previews, terrain/foundation response rules, controller targeting, collision policy, and save/undo compatibility. This is assigned to M2 but does not authorize implementation before M2 becomes active.

## Rejected and out of scope

### IDEA-002 — Cars and traffic simulation

**Status:** Rejected  
**Added:** 2026-09-08

Modern cars and traffic simulation do not fit the intended setting. Do not propose them as a transportation solution.
