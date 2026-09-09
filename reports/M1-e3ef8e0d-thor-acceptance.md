# M1 physical Thor acceptance — e3ef8e0d

Date: 2026-09-09. Status: **M1 complete** for the bounded editable-cottage,
continuous-terrain and landscaped-riverbank scope. This does not authorize M2.

The player explicitly requested direct ADB validation of the final vegetation-wind
build and asked that the milestone be called complete when the required Thor tests
passed. Earlier accepted Thor checks for the unchanged cottage, terrain, controller,
resize, recovery and house-action paths remain valid and were not needlessly repeated.

## Exact build

- Commit: `e3ef8e0d4d27f02a95b820898b71b7959e7897a8`.
- APK: `hearthvale-m1-repair-e3ef8e0d.apk`, 38,915,603 bytes.
- SHA-256: `2fc1bf9b320b43d2a126f63db376a63ad6e1df24c10a5bcd6fc1cec34273d102`.
- Package: `org.hearthvale.game.repair.ce3ef8e0d`, version code 6,
  `0.1.3-repair-e3ef8e0d`.
- CI receipt verifies the signature, Mobile renderer, ARM64-only archive, pinned
  native voxel library and exclusion of development resources. Installation as a
  separate test app succeeded without replacing or clearing any existing build.

## Device and runtime

- Physical AYN Thor, Android 13, security patch 2024-01-01.
- Built-in display tested in landscape at 1920 × 1080 and 60 Hz.
- Godot 4.7.2 ran Vulkan Forward Mobile on Qualcomm Adreno 740.
- Android reported the built-in `Odin Controller`; Godot mapped both sticks and
  both triggers (six axes).
- Android Game Mode reports `Unsupported`; no performance-mode setting was changed.
- The optional `game-dev` CLI was unavailable, so evidence was collected with the
  repository's documented ADB route and Android SurfaceFlinger directly.

## Physical behavior

- Real events sent through the Thor controller device changed tools via D-pad,
  moved the cursor/camera via the left-stick axis, planted foliage and trees with
  A, switched between Terrain and Building, opened the house action chooser,
  navigated Pause, and saved.
- The foliage brush produced varied small foliage at the selected terrain point.
  The tree brush respected spacing exclusion and then planted on clear ground.
- Two physical-device frames three seconds apart changed 14,540 world pixels.
  Inspection showed the tree crowns in different sway positions with grounded
  trunks and no palette, scale or seam regression. Newly brushed foliage and trees
  use the same animated gameplay path as starter vegetation.
- Menu focus blocked the world as expected. Android Home followed by app return
  restored the game paused, so an interrupted edit cannot resume implicitly.
- No Godot script error, native crash, ANR, fatal signal or out-of-memory event was
  present during launch, interaction, the timed run, cold restart or resume.

## Save and cold restart

Pause-menu Save published generation 1. The manifest contained 92 landscape
records (`next_id: 93`), including the newly brushed foliage and tree records.
After force-stop and cold relaunch, the same records rendered in the scene and both
checkpoint hashes were unchanged:

- Terrain payload: `3982e904caf9748058c37a5e42fe4c422bb8f8e6f69c2d18bf28022b4758d505`.
- Manifest: `1dfa16862d093eb80b8e75c81bf5e54b3eae2e9072f3c450a8ca2e402f6a9ce8`.

## Ten-minute performance run

The app remained active for 10 minutes 41 seconds while the real controller route,
planting, close tree view, cottage action menu, pause and save were exercised.

- Hearthvale SurfaceFlinger layer: 38,207 frames, 0 dropped, 0 late-acquire.
- 38,072 frames presented at 16 ms; 132 at 33 ms; one each at 66 ms, 118 ms
  and 1,000 ms. The long sample includes deliberate menu/save/capture interruptions.
- Reported layer average: 62.156 FPS with a 60 FPS vote on the 60 Hz display.
- The in-game close-tree view reported 59–60 FPS, 20.48–20.53 ms process time,
  724–726 draw calls and about 2.57 million triangles.
- Battery temperature rose from 26°C to 28°C; Android thermal status stayed 0
  (no throttling). Battery changed from 76% to 75%.
- PSS samples were 928 MB near launch, 913 MB at midpoint and 990 MB at the final
  close view. No monotonic growth or memory failure was observed.

The measured frame distribution meets the M1 60 FPS target at both the 95th and
99th percentiles, with no dropped SurfaceFlinger frames.

## Captures

- `reports/screenshots/m1-e3ef8e0d-thor-tenmin.png`: close planted-tree view at
  the end of the sustained run with the device performance overlay.
- `reports/screenshots/m1-e3ef8e0d-thor-resume.png`: safe paused state after
  Android Home and resume.

TV/dock and a separate external controller were not connected for this final pass.
They are product-polish coverage, not blockers for the bounded handheld M1 scope.
