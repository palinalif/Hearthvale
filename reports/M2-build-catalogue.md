# Bottom-half construction browser — 2026-09-11

Player request: replace the building X menu's separate placement commands with a Sims-like lower-screen catalogue, using real model previews and categories. This extends the existing M2-04 catalogue hub; the previous implementation was a hub and text menus, not this grid.

## Implemented candidate

- X in ordinary Building play, over the shell or empty space, opens the lower-half browser. X over an existing decoration retains its Colour/Variation/edit controls; A retains direct roof/wall/section editing.
- Windows, Doors, Wall decor (flower boxes and standalone shutters), Roof decor (chimneys, dormers and weathervanes), Homes. Entries are derived from the existing installed variant and recipe tables, including arched/awning/sliding/bay windows.
- Thumbnail cards, concise names, category tabs, focus outline, scrolling. D-pad browses; LB/RB change categories; A starts placement; B/X closes. Mouse/touch can use cards/tabs/scroll. Y opens existing House options for recovery and less-common management; Landscape opens the existing global terrain/path/garden hub. The global Up/Tab hub is retained, not claimed redesigned here.
- Item choice hides the browser and restores the full world view. Cancel returns to the same category and item. Existing placement engines retain footprint previews, IDs, validation, one-edit confirmation, undo/reload and individual decor colours. Menu input cannot reach world tools; interruptions close the browser without restarting it.
- A single private 160x128 SubViewport renders reused gameplay model builders on demand. ImageTextures are cached (64-entry cap), no online assets, no separate live viewport per card; hidden/completed queues stop rendering. Thumbnail models/signatures stay out of gameplay records. Temporary camera offset makes space above the panel and is restored on every exit.

## Validation

`m2_build_browser_test.gd` exercises physical controller entry/category/item selection, multiple window sizes, exact variants, read-only browsing/preview, cancel/reopen memory, camera restoration, outside-click isolation and interruption safety. Actual Mobile mode requires a rendered thumbnail on every card, checks the shared/cached renderer and captures all five categories. The normal placement gate runs both modes before export. A focused workflow runs the same test for fast feedback; the existing full delivery remains required.

The physical recovery test now enters House options with Y from the X browser; its entire existing row order, recovery-item choice and cancellation assertions remain. No legacy UI/controller/placement test is disabled. Inherited prototype-scene tests still exercise their original APIs.

At source preparation: source/diff review only; no local Godot executable is installed, and the current GitHub clone attempt failed DNS. Pinned CI runtime, actual Mobile captures and verified APK/Drive delivery are pending. No new build is delivered or merged by this report. The lead exposed in this session is GPT-6 Astra Pro rather than the repository's preferred Sol; no model switch or subagents used. User's earlier permission to continue without waiting for APK export does not make an unverified package a delivered artifact. Physical Thor performance/usability requires a new player test.

Sources for the renderer/camera API contract: Godot official Camera3D and SubViewport class documentation (https://docs.godotengine.org/en/stable/classes/class_camera3d.html and https://docs.godotengine.org/en/stable/classes/class_subviewport.html). Existing project plans: HANDOFF.md, tasks/M2-hamlet-building.md, reports/M2-04-global-build-catalogue.md. No reference-game assets are used. Lighting/art polish remains separate.
