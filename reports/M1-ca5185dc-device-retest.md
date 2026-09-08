# ca5185dc — physical Thor retest, 2026-09-08

## Player evidence (not CI inference)

The player passed specific-cottage hover/X entry; idle B exit without pause or camera teleport; operation-first cancellation; geometric crosshair; visible window outline/prompts; deliberate A-move horizontally and vertically with the opening following; move cancellation; escaping alignment snapping; visible-side-only targeting; two-cottage selection and edit/colour isolation; unobstructed style pickers; colour cancel/commit; and the recolour/orbit Z-fighting check.

Camera-facing attachment start, free movement, displacement preservation, recovery cancellation/confirmation, free duplication camera and its return on confirm/cancel passed. **Recovery is partially accepted:** the player had to use the left stick to reach Needs placement because D-pad navigation did not reach the displayed entry as expected.

Building-mode ground-hover prompts, Save/edit/Reload/Resume/immediate sculpting, same-test-app relaunch persistence, Raise/Dig 3 versus Smooth 5 defaults, per-tool strength memory, quicker brush settings and clean return to sculpting passed. This does not validate migration from an older app.

**Failed:** Raise while moving the brush remains jumpy and wants to stay at the highest point.

## Follow-up scope

Keep the accepted cottage interactions. Repair D-pad menu ordering and terrain camera/navigation. Direct resize handles, comprehensive manual-window resize/layout stability, one-block overhang work, Slope performance/plane guide, visual UI polish and stable signing remain separate outstanding work.

### D-pad reproduction

The recovery button was appended to `_building_buttons` but inserted before Close in the VBox. D-pad traversal used insertion order, unlike the displayed order and spatial stick navigation. Traverse the visible displayed rows; exclude disabled, hidden and queued-for-deletion controls. New full-scene test enters through physical X, reaches the recovery entry using only D-pad presses (no injected focus), and selects between two actual recovery items.

### Terrain reproduction and proposed correction

The previous camera lerped to `cursor.y + 2`, while Raise/Dig commit transfers the edited frontier into `cursor`. This retains a height-chasing camera. Ground targeting also has a bounded probe around that retained altitude; its fallback can pick nearby higher geometry rather than the ground column the player travelled to.

The follow-up gives the navigation camera its own height goal. Holding, committing or cancelling sculpting must not move that goal; X/Z pan, orbit and zoom remain available. Between strokes, deliberate travel in Ground reference samples the exact cursor column (nearest floor below the hint, or the top of the connected solid span containing it). It never searches sideways for a peak and never overrides an active sculpt frontier or Wall/Ceiling reference. Camera height advances once per input tick with a three-world-unit/second speed cap and easing. Rendering the camera multiple times must not advance it again.

Only one native vertical column is inspected per navigation sample. There is no heightmap replacement, full-world scan, save-schema change or alteration to native sculpt transactions. Device performance of this addition is not yet measured.

## Evidence status

Implementation and new full-scene tests prepared on the follow-up branch; CI and a new APK are pending. `ca5185dc` remains the physically accepted baseline with the two exceptions above. No claim of M1 completion.
