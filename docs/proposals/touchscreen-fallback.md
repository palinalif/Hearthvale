# Touchscreen fallback — full proposal (gesture-based)

**Date:** 2026-09-16
**Backlog entry:** IDEA-008 (Candidate)
**Goal:** playtest Hearthvale on a phone with fingers alone when no controller is connected. Controller connect hides the touch layer and restores controller behaviour; disconnect restores touch. The touch scheme maps onto the *same* `InputMap` actions the controller uses — no forked game logic, identical commit/undo semantics.

## 1. Input layer architecture

- A `TouchInputController` node (or `_process_input` block in `m1_scene`) is active only while no joypad is connected. Detection polls `Input.is_joy_connected()` each frame plus joypad connect/disconnect notifications, with a short debounce to avoid flapping.
- Recognized gestures synthesize the existing actions (`Input.action_press/action_release` for discrete verbs; held-state emulation for the axis-style actions `m1_move_*`, `m1_orbit_*`, `m1_zoom_*`). Every gameplay system therefore sees exactly what it sees today.
- While a controller is connected, the touch layer stops consuming events and any transient touch UI is hidden. Handoff never commits, cancels, or places anything: an in-flight gesture is discarded on switch, mirroring the existing held-brush disconnect rule.
- Keyboard (PC) bindings are untouched.

The 22 actions to cover (from `m1_scene.gd`): accept, cancel, pause, tools, precision, view, undo, redo, move L/R/U/D, orbit L/R/U/D, zoom in/out, height up/down, cycle L/R, debug, focus.

## 2. Gesture grammar

Design principles: **one finger is context-sensitive (the "world hand"), two fingers are always the camera, taps are the confirm verb, edge swipes are the system verbs.** No permanent button row; the only persistent chrome is a small transient hint strip that fades after ~3s in each mode.

### 2.1 Camera and navigation (play mode)

| Gesture | Action |
|---|---|
| One-finger drag | Camera orbit (horizontal) + pitch (vertical), mapping to `m1_orbit_*` |
| Pinch in/out | `m1_zoom_out` / `m1_zoom_in` |
| Two-finger drag | World-cursor move (`m1_move_*`) — drag the world to steer the cursor |
| Two-finger vertical drag (bias detected) | `m1_height_up` / `m1_height_down` |
| Tap (world, not UI) | `m1_accept` at the tapped ground point — cursor snaps to tap, confirm fires |

Cursor/height feel is tuned with the same deadzones the stick actions already use (0.18 move, 0.05 zoom).

### 2.2 Sculpting

| Gesture | Action |
|---|---|
| One-finger drag | Paints/digs with the active brush (held `m1_accept` while touching) — the finger *is* the brush |
| Tap | Single-cell commit at the tapped cell (one undo transaction, as today) |
| Pinch / two-finger drag / two-finger vertical | Same camera controls as play mode |
| Swipe from left edge | Open the tool menu (same as `m1_tools`) |
| Swipe from right edge | Tool cycle (`m1_cycle_left` / `m1_cycle_right`) |
| Long press (world) | Small radial: **Undo · Redo · Tools · Focus** (`m1_undo`, `m1_redo`, `m1_tools`, `m1_focus`) |

Lifting the finger stops the brush; app focus loss or an interrupting gesture cancels any held paint, matching the controller disconnect rule.

### 2.3 Placement and rotation (furniture, paths, fences, details, homes)

| Gesture | Action |
|---|---|
| One-finger drag | Moves the ghost with the finger (screen-space to world projection), continuous |
| Two-finger rotate (twist) | Rotate the object in the same yaw steps as `m1_cycle_*` — one 45° of twist = one step; no separate rotate button exists in-game, so this is the rotation verb |
| Pinch | Zoom, so the ghost can be inspected closely |
| Tap (on ghost) | `m1_accept` — confirm placement (one undo transaction) |
| Tap (elsewhere) | Moves the ghost there |
| Swipe from left edge | Back to catalogue / cancel (`m1_cancel`), restoring the exact prior state |

The validity UI (ghost colour, outline, status icon, reason label) is identical to the controller flow; it must stay readable at 720p.

### 2.4 Menus and catalogues

Menus keep the normal Control-node touch handling (buttons are tappable, lists scrollable by one-finger swipe) — that is the standard Godot mobile UX and respects the existing "menus block world input" contract.

| Gesture | Action |
|---|---|
| Tap item | Select (accept) |
| One-finger vertical swipe | Scroll (the 22-style two-column street-furniture grid fits one page; home catalogue may scroll) |
| Swipe from left edge | Back (`m1_cancel` / `m1_pause`-menu close) |
| Swipe from right edge (in catalogue) | Next category |

### 2.5 System verbs

| Gesture | Action |
|---|---|
| Swipe down from top edge | Pause (`m1_pause`) |
| Long press (anywhere, incl. menus) | Radial: **Undo · Redo · Tools · Focus · Pause** |
| Double tap | `m1_focus` (the one verb with no other natural slot) |

Precision mode (`m1_precision`) enters automatically when a placement ghost is near a snap threshold and is toggled from the radial; it is not a primary touch verb.

### 2.6 Conflict-resolution rules

- Two-finger events always win: as soon as a second finger lands, any in-progress one-finger gesture is aborted without firing.
- Edge swipes start in a 24px border band and must leave the band within 100ms or they fall through to normal gestures.
- A tap is a tap only if the finger moved <12px and held <250ms.
- Long press fires at 500ms; movement >20px before that converts to a drag.
- World taps are ignored while any menu is open (menus block world input).

All thresholds are `ProjectSettings` constants so phone playtest can tune them without code changes.

## 3. Transient UI chrome (the honest exception)

Pure gesture has no discovery problem for one player, but a new gesture needs *something* to look at. Minimal chrome, all auto-fading:

- A 2-line hint strip at the bottom edge per mode ("1 finger: paint · 2 fingers: camera", "drag: move · twist: rotate · tap: place"). Fades after 3s, reappears on mode change.
- The long-press radial (5 items max, existing glyph icons from the controller prompt system).
- No persistent buttons. If phone playtest shows gestures under-performing for a specific verb, the fallback is a *single* small optional on-screen button for that verb behind a ProjectSetting — not a row.

## 4. Phasing and acceptance

**Phase 1 — foundation (input layer + camera + menus):** connect/disconnect detection and handoff safety; play-mode camera (orbit/pinch/two-finger move/height); tap-to-act; menus tappable/scrollable; pause edge swipe; hint strip. *Acceptance:* on a phone with no controller, open a save, orbit/zoom/pan, open every menu (world browser, 22-style street-furniture grid, pause), select and back out — no controller needed, nothing committed by accident.

**Phase 2 — sculpting:** one-finger paint/dig, tap single-cell, tool menu and cycle swipes, long-press radial with undo/redo/focus; held-brush rules on gesture end and focus loss. *Acceptance:* sculpt a change of ≥3 cells, resize a region, undo/redo via radial, every commit one undo transaction; full M1 sculpt regression green.

**Phase 3 — placement:** ghost move/twist-rotate/tap-confirm/edge-cancel across furniture, paths, fences, details, and homes; validity UI at 720p. *Acceptance:* place, rotate and cancel a street prop and a home entirely by touch; cancel restores exact prior state; duplicate/move-existing via long-press radial + placement gestures.

**Cross-cutting acceptance (all phases):**

- Touch input maps to the same actions: a new test synthesizes `InputEventScreenTouch`/`InputEventScreenDrag` sequences and asserts the resulting action presses (e.g. twist → `m1_cycle_right` ×N, pinch → `m1_zoom_in`).
- Handoff test: simulated joypad connect hides the touch layer and stops touch consumption mid-gesture without side effects; disconnect restores.
- Existing controller, placement, sculpture and regression suites remain green (they are the authoritative controller contract).
- Playtest APK with the touch scheme uploaded through the gated Drive workflow before handoff; phone review is the player's gate — a green CI is not visual acceptance.

## 5. Estimate and model

**Implementation estimate:** 8–14 active hours (Phase 1 ≈ 3–5h, Phase 2 ≈ 3–4h, Phase 3 ≈ 3–5h).
**Estimate assumptions:** The action layer already exists and is the single mapping target; no new save schema, world, or rendering work; menu nodes already accept touch via Godot's Control system; tuning time on a physical phone is *not* included.
**Estimate confidence:** Medium — gesture feel (twist-rotate especially) is the main unknown and may need a second phone pass.
**Recommended model:** Sol / medium.
**Model rationale:** Coupled input-layer and UI-state work across the scene with strict safety contracts (handoff, held-gesture, menu blocking) — exactly the profile Sol/medium is mapped to; there is no substantial standalone visual-design portion.
**Acceptance outline:** A phone with no controller can open a save, sculpt, place/rotate/cancel a prop and a home, undo, use every menu, and save — entirely by touch; controller connect/disconnect handoffs are side-effect free; all existing regression suites stay green; gated playtest APK delivered.

## 6. Known risks

- **Twist-to-rotate feel** may fight pinch-zoom on small screens; mitigation: rotation is only active during placement mode (pinch there is zoom, twist is rotate — both two-finger, disambiguated by dominant rotation vs. scale), and the step size is one coarse yaw increment so overshoot is one step.
- **One-finger paint vs. one-finger orbit** in play mode: the scheme keeps play mode orbit-first; if playtest wants to sculpt without entering a tool state, the radial already exposes Tools.
- **Accidental edge swipes** while orbiting: the band+timing rule in §2.6; edge swipes never fire confirm/cancel-class actions except the explicit cancel/pause ones, which are individually safe (cancel restores state).
- **Threshold tuning on the actual phone** may need one extra pass after the first playtest APK.
