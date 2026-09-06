# M1 controls — follow-up build

The first Thor playtest exposed a real mode-routing failure. The follow-up uses separate Terrain and Cottage modes and action menus. Physical comfort must be checked again on version 0.1.1-m1-rework.

## Shared controls

- Select/Back switches Terrain and Cottage modes and cancels any pending edit.
- Left stick moves the terrain target; right stick orbits; triggers zoom.
- X opens actions for the current mode only. D-pad up/down chooses an action, A selects, B closes.
- LB/RB undo/redo; Start pauses and provides Save/Reload; L3 toggles precision; R3 refocuses; Y toggles debug information.

Mode changes, menus, pause, focus loss and controller disconnection cancel unfinished work. A held action cannot restart until released and pressed again. The visible mode and action prompts describe what A will do.

## Terrain

Choose Raise, Dig, Level, Slope or Smooth from the Terrain menu. Hold A to sculpt, move while holding to draw a connected stroke, release to commit one undo transaction, or B to cancel the whole stroke.

The contrasting centre marker identifies the target even when geometry obscures it. The thin local highlight and faint ghost show the area of influence, not an instantaneous exact cut. An unavailable target is labelled explicitly.

The tools menu contains radius, strength, falloff, reference direction, fixed-plane resampling/keep-reference and optional height snapping. D-pad up/down adjusts aiming height. Ground/wall/ceiling references support raise/dig; level/slope/smooth use ground references for pads and banks. Flatten references remain fixed during a stroke. No mouse, touch or keyboard is required.

## Cottage

D-pad left/right selects a cottage. A starts a resize preview; left/right selects width/depth, left stick changes that dimension, and up/down changes height. A commits and B cancels. L3 provides finer increments. Handles follow the cottage's actual transform.

X opens cottage actions, without terrain tools. D-pad left/right cycles its details; up/down selects an action. Move, replace, suppress/restore, add a flower box, recover an unsupported detail, change material or duplicate the cottage. While moving a detail, the left stick operates in its supporting wall plane; orbit and zoom remain available.

New cottages use half-scale proportions: 9 × 5 × 7 world units for the initial shell, with coherently scaled roof and details. Existing saves retain their authored scale. Choose **Miniature scale** in Cottage actions to convert the selected older cottage in one undoable operation. Local dimensions, attachments, manual choices and position are preserved.

## Regression and physical review

Retain the full six-window regression from the M1 ticket: move, replace, suppress, add a flower box, resize, change material, undo/redo, save/restart, duplicate independently, shrink past an attachment, delete support and recover it.

Specifically repeat the reported failure: switch from Cottage to Terrain, choose Dig, then hold A and move. Only terrain must change; the cottage must never start resizing. Repeat with Raise and through menu/mode interruptions. Check the centre marker near, far and behind the cottage.

Run the [Thor checklist](M1-thor-playtest.md). Automated state checks and desktop screenshots do not establish handheld comfort. No catalogue expansion follows without the required review.
