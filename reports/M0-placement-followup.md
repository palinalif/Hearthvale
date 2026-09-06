# M0 terrain placement follow-up

Date: 6 September 2026. Scope: the player's Thor feedback that controls feel clunky and the add/remove position is hard to judge. This is an M0 interaction correction; it does not change terrain resolution, saves, dependencies, or start M1.

The lead found that the old target sphere appeared only after A, was drawn through terrain without sufficient depth cues, and committed the current moving cursor rather than a fixed confirmation target. Luna workers own the native read-only preview query and presentation/controller changes in separate files. The lead owns review, configuration, integration checks and Android exports.

## Implemented behavior

Show affected cells before committing, distinguish ADD and REMOVE with colour and text, indicate empty/no-op targets, and make brush height relative to nearby terrain visible. Gentle stick input should produce slower fine movement. A locks the preview's parameters while orbit and zoom remain available; A again applies it, or B cancels. The preview must agree with the native operation without mutating authoritative terrain, undo history, or saves.

Further player feedback explicitly rejects the thick cyan circle. The affected-cell highlight and a restrained thin outline should become the primary cursor, with only a small secondary marker for its centre/depth.

The player also requested a ghost preview volume. Show a faint full brush envelope in both live aim and locked confirmation, alongside the more legible exact affected-cell highlight. Empty targets retain the volume cue while reporting that no cells would change.

`TerrainBackend.preview_sphere` and `apply_sphere` share the same native cloned-buffer sphere operation. The presentation caches results by half-cell target, radius, mode, backend identity, and authoritative revision. The changed cells become a batched exposed-face highlight and thin crease/boundary lines; internal faces and coplanar internal edges are omitted. The full brush sphere remains faintly visible through terrain. All of this is derived preview geometry; the existing native backend remains the only authoritative terrain implementation.

The target marker has a fixed small size, and its displayed coordinates preserve half-cell positions. A vertical guide runs from the target to a nearby floor sample below it; it is a depth aid, not surface snapping or a cutaway view. ADD is amber and REMOVE is cyan, with text as well as colour. Small stick input has a nonlinear slower response while full input retains travel speed. While locked, cursor movement, mode, radius, and height changes are blocked; orbit and zoom remain available. B cancels a lock, or opens pause when unlocked. Undo/redo, reload, focus loss, and disconnection cancel the preview. Placement visuals hide during menus, fixture results, loading, and restoration; the running benchmark keeps the live preview workload visible.

The Android follow-up uses version code 2 / version name `0.0.2-m0`, the existing application ID and development signing identity. Previous `0.0.1-m0` APKs are preserved locally under `builds/archive/0.0.1-m0`. The original report's artifact hashes and 60-second measurements remain historical evidence for that build.

## Verification

The lead ran the full `tools/check.ps1` suite: native dependency probe, **38 checkpoint checks**, separate-process checkpoint fixtures, **83 backend checks**, and the controller regression all passed. The malformed-depth checkpoint case retains its intentional native warning. Backend tests compare complete native voxel buffers to verify exact changed-set parity and preview immutability. Controller tests cover fractional targets, ghost alignment, actual commit versus displayed cells, locking while orbiting, fine movement, no-op volume visibility, thin-outline geometry, cancellation, menu hiding, save/reload, focus/disconnect, and fixture isolation. The controller regression was rerun after the final HUD/target fixes and passed with zero failures.

Lead-rendered Mobile captures for ADD, REMOVE, locked confirmation, and the tunnel were inspected. Review increased thin-outline contrast against grass, moved the debug panel below the placement text, and corrected target labels to show fractional coordinates. Final screenshots are under `reports/screenshots/placement-*.png`. Temporary whole-project parse failures occurred while the two scene/helper files were being integrated; the stable integrated suite passed afterward.

## Desktop renderer measurements

Final runs used the same 60-second route and native edit/undo/redo/save sequence, 1280 × 720, RTX 3070, `--disable-vsync --max-fps 60`. Initial terrain loading is outside the interval; live preview queries and highlight geometry updates are included. Each renderer completed 30 edits, 30 undos, 30 redos, and 30 saves, with no script/native errors.

| Metric | Mobile | Compatibility |
| --- | ---: | ---: |
| Elapsed seconds / samples | 60.007 / 3,576 | 60.012 / 3,574 |
| Frame p50 / p95 / p99, ms | 16.666 / 16.698 / 17.122 | 16.666 / 16.720 / 17.124 |
| Maximum frame, ms | 52.378 | 68.855 |
| Edit + undo + redo + save cycle p95, ms | 46.114 | 45.085 |
| Final draw calls / drawn primitives | 35 / 67,280 | 74 / 67,300 |

These are small desktop fixtures, not sustained Thor performance claims. Save cycles still exceed a 16.7 ms budget. Drawn primitives include passes/UI; Godot static-memory counters are not process or GPU memory. Exact GPU memory remains unmeasured. JSON with full counters/context is in `performance/placement-mobile.json` and `placement-compatibility.json`.

The first Compatibility run had one **616.697 ms** frame; a 20-second diagnostic repeat peaked at 62.877 ms. The lead subsequently found and stopped a stale headless controller-test process left from intermediate worker integration. Both final 60-second runs above started with no other Godot process and after renderer diagnostics. The original runs and short repeat remain in `performance/placement-*-initial.json` and `placement-compatibility-repeat.json`. The cause of the original outlier is unconfirmed; the final run does not prove it cannot recur.

## Builds and physical playtest

The lead ran `tools/build.ps1 -Windows -Compatibility`. Android debug, release, and Compatibility APKs exported successfully, as did Windows debug/release and Compatibility release. The Compatibility export restored `project.godot` byte for byte. All three APK signatures were verified against the previous build's certificate; application ID, version code/name, and Mobile/OpenGL manifest metadata were checked. Each APK contains only ARM64 native libraries, matches the pinned voxel binary, and excludes development/MCP/reference resources. Exact sizes and SHA256 values are in `placement-apk-verification.json`.

Each exported Windows executable independently ran the native fixture for three seconds, completed two edit/undo/redo/save cycles, and exited zero without logged errors. The Compatibility executable selected OpenGL without a renderer command-line override. Results are in `placement-windows-verification.json`. The engine, official templates, native extension, save schema, and signing identity remain those recorded in the original M0 report.

ADB listed zero authorised devices at the final check. This follow-up's physical Thor checks are **not run**. The player's earlier successful Thor test applies to the original build; it does not establish that the revised placement feels better. The pinned MCP limitation remains unchanged.

Install `builds/hearthvale-m0-debug.apk` as an update, preserving saves. In particular, playtest these three points from `docs/thor-playtest.md`:

1. Aim ADD and REMOVE across a surface edge and inside the tunnel. Judge whether the faint sphere, thin voxel outline, and small depth marker make the result predictable.
2. Use small stick nudges, lock with A, orbit/zoom, then A to apply or B to cancel. Compare the affected-cell highlight with the actual result and undo it.
3. Save, quit, and reload your existing terrain. Report whether the new controls feel clearer and whether the highlight is too faint or too prominent on the Thor.

M1 had not started at this follow-up handoff. The player subsequently authorized the editable cottage, continuous terrain sculpting and supporting visual checkpoint. This does not change any M0 test result or close its outstanding checks.
