# M2-06 — Roads & Paths vertical slice

**Status:** implemented and delivered on `feat/m2-hamlet-building` on 2026-09-09.

## Player-facing result

The global Build Catalogue now opens a real **Roads & paths** submenu with three
styles: packed earth, cobblestone, and stepping stones. Choosing a style enters
an in-world, read-only path preview. The existing camera remains usable while
the cursor samples the native terrain surface.

Controller prompts are:

- A — add a point;
- X — finish and confirm the path;
- B — cancel without changing the world;
- LB — remove the latest point;
- right stick — orbit; LT/RT — zoom.

The preview renders the current polyline, a validity marker, and a plain-language
reason when placement is blocked. A finished path is committed only after a
second validation pass. Committing the path and clearing nearby planting is one
landscape history transaction; cancel, pause, focus loss, disconnect, or stale
revision rejection restores the exact pre-preview landscape without creating
history.

## Authoritative contract

`LandscapeState` keeps `paths` optional for old saves. Each path has a stable ID,
style ID, snapped width, and snapped X/Z points. Validation enforces:

- at most 32 paths;
- 2–64 points per path;
- widths from 0.25 to 3.0 world units;
- native-grid point coordinates inside the 48-unit editable world;
- meaningful non-zero segments;
- a bounded estimated render-cell budget;
- unique IDs shared with planting records.

Paths are presentation-only geometry. They never sculpt or rewrite native voxel
terrain. Strict interior crossings of home footprints are rejected, while an
endpoint touching an edge is allowed for a natural approach to a home.

## Verification

- `tests/m2_path_state_test.gd`: 18 checks, 0 failures.
- `tests/m2_path_placement_test.gd`: 30 checks, 0 failures.
- `tests/m2_path_render_test.gd`: 14 headless checks and 16 actual-render checks, 0 failures.
- `tests/m2_home_catalogue_test.gd`: 38 checks, 0 failures.
- `tools/test-m1-placement.ps1`: passed with the new path gates included.
- `tools/check.ps1`: passed.
- Pinned Godot 4.7.2 import: passed.
- Desktop Godot 4.7.2 Forward Mobile/D3D12 capture: [all three path styles](../reports/screenshots/m2-paths/all-styles.png).

Desktop Mobile output is visual-development evidence only. Physical Thor feel,
performance, and player visual approval remain separate acceptance records.

## Delivery

Source commit `822ffaa6620436240e9dc22ba720869527c98be4` passed verified
delivery run `34404866082`. The run produced and verified the isolated ARM64
APK and Windows x86-64 playtest ZIP, then uploaded both packages and their
receipts to private Google Drive.
