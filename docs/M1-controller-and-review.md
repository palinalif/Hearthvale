# M1 controller route and review requirements

This is the integration contract, not a claim of completed implementation or Thor validation. Read both M1 tickets. Physical checks below are **not run** until the player tests the new build.

## Shared controls

Preserve left-stick fine movement, right-stick orbit, triggers zoom, LB/RB undo/redo, Start pause, Y debug and R3 focus. Use View to switch terrain/building context and L3 for a visible precision toggle. D-pad and A/B operate menus; menus consume input and cannot modify the world behind them. Contextual labels must explain the current operation without covering the working area.

## Sculpting

Terrain defaults to continuous sculpting. A press begins, holding applies time-based influence, and release finishes one transaction. B during a stroke restores the entire pre-stroke terrain. Pause, disconnect and focus loss cancel uncommitted work and require release followed by a fresh press. Keep the target stable through excavation.

X opens the scrollable tools/settings menu: raise, dig, horizontal level, slope level and smooth; radius, strength, falloff, keep reference, resample, and optional height snap. D-pad up/down changes cursor height; adjust radius in the menu. Ground, wall and ceiling references support raise/dig; level, slope and smooth use ground references to extend pads and banks. The faint influence volume is distinct from the exact changed-cell ghost retained in the separate M0 stamping scene. Flatten tools show their fixed reference plane and height. Sampling uses the centre terrain hit; no hit is an unavailable state, not an invented plane.

## Cottage

D-pad left/right cycles cottages. A begins resizing; D-pad left/right chooses width/depth, the left stick changes that axis, and D-pad up/down changes height. A commits and B cancels. L3 changes the increment from 1 to 0.25 world units. Visible handles identify the three dimensions. Orbit and zoom stay available while inspecting a preview.

X opens details/actions. D-pad left/right cycles generated, manual, suppressed and needs-placement records; up/down selects actions. Move in the supporting wall plane; replace; suppress/restore; add a flower box; choose another surviving wall with Support next/previous and reattach; change material; duplicate the same cottage. The recovery list remains reachable after shrinking or deleting support. The M1 detail set contains windows and flower boxes; it does not add roof-mounted decorations.

## Required controller playtest

Run the full cottage ticket scenario with six automatic windows: move one, replace another, suppress another, add a flower box, widen, shorten, change material, undo/redo, save/restart, duplicate and edit the copy independently. Shrink past a moved attachment and recover it. Delete its support and reattach it. Cancel a resize. Verify the rendered result follows the persistent records.

Around that same cottage, hold raise and dig stationary, drag a connected stroke, extend a level pad with a fixed height, retain that height across strokes, resample, extend a slope, smooth its edges, and excavate a wall without losing the overhang. Cancel, undo and redo whole strokes. Save and cold restart. Open menus and disconnect/reconnect while holding A: no unattended sculpting may resume.

Record controller comfort, target legibility, fine terrain/detail scale and visual feedback separately from automated tests. Review a normal-distance and a close view against Town to City and Station to Station. No catalogue expansion follows without the required visual review. Retain the separate unresolved M0 checklist.
