# M0 — prove the platform before building the game

**Status:** ready for implementation planning; not executed.  
**Blocks:** every later milestone.  
**Objective:** one reproducible native Android ARM64 test scene that proves the engine/voxel/controller/save path on the actual Thor Max.

Read `../AGENTS.md` and sections 8–13 of `../docs/design.md` first. The candidate versions and primary sources are in the design; they are not a prevalidated bundle.

## Bounded deliverable

A small volumetric terrain patch, an orbit camera and world cursor, controller-driven add/remove terrain, a visible tunnel or overhang, one directional sun, a simple water-material test surface, and save/reload of modified terrain. Include a frame/memory/debug overlay. The water surface is a rendering experiment, not the completed water-editing feature.

Keep the editor MCP smoke test separate from the game scene and the Android runtime. A missing MCP connection does not justify faking a live-editor result.

## Work sequence

1. Inspect the development host, repository, available Godot installation, Android SDK/JDK setup, and authorised device connection. Record what actually exists. Do not invent device access.
2. Resolve and pin an engine/export-template/voxel-package combination. Confirm the package contains or can build the required Android ARM64 debug and release libraries. Test desktop loading first, then export and device loading before creating additional systems.
3. Build the minimal scene and action-based controller route. Selection and brush previews must be visible. A tunnel proves that editing is volumetric rather than a heightmap modification.
4. Persist changed terrain and reload it after fully restarting the app. Test an undoable bounded stroke, and verify cancelled previews do not change saved data.
5. Compare Mobile and Compatibility on the same fixture where supported. Record actual configuration, visible geometry counts, frame times, edit stalls, memory, and native errors. Lack of exact GPU memory telemetry should be stated rather than filled with an estimate labelled as measurement.
6. Install and smoke-test the tagged MCP bridge using a disposable editor scene. Verify inspect → change → save → restart → inspect, plus an intentional script error and its correction. Review the generated client configuration and keep the service private.

## Acceptance checks

| Check | Required evidence |
| --- | --- |
| Dependency loading | Exact versions and package origin; desktop result; Android debug and release result. |
| Native execution | Reproducible build/install steps and app launch on the actual Thor; no compatibility layer. |
| Controller | Built-in pad can navigate, orbit, add/remove terrain, cancel, undo, save, reload, and quit without touch. |
| Volume | A tunnel with intact terrain above it, or an equally clear overhang demonstration. |
| Persistence | Before/after/restart comparison for modified terrain; distinguish cached visuals from loaded world data. |
| Performance | Repeatable scene and camera route; resolution and device mode; observed frame pacing and edit costs. |
| Failure handling | Controller disconnect and app suspension do not leave an active destructive brush or corrupt the save. |
| MCP | Client/server/editor versions, actual operations verified on disk, and any unsupported operations identified. |
| TV path | When a dock/display/external pad is available, test the single-screen route; otherwise mark this check not run. |

## Results report

Create an implementation report recording date, operating systems/firmware, engine hash/version, export-template version, addon tag/commit, tested renderers, build steps, log locations, and each acceptance result. Distinguish “passed on desktop,” “passed on Thor,” “failed,” and “not run.” Keep identifying secrets out of the report.

The full warm-up/thermal benchmark belongs to the later representative scene. M0 still needs enough runtime to reveal immediate crashes, repeated edit stalls, and basic renderer incompatibility; do not call an empty-scene frame counter a game benchmark.

## Failure route

When GDExtension fails, inspect the actual error and test a supported module route or compatible pinned version. Report the tradeoff before adopting a custom engine build. Stop for approval before switching engines or writing a new voxel engine. Do not remove caves or silently fall back to a heightmap.

## Explicitly excluded

Villagers, building catalogues, smart roof joining, advanced water, procedural biomes, multiple architectural kits, general-purpose editor frameworks, and remote server orchestration. M0 exists to answer a narrow question with device evidence.
