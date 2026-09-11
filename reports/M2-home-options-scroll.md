# M2 home-options layout prerequisite — 2026-09-10

Scope: player-approved repair of the home-options panel overlapping the controller prompt bar on `feat/m2-visual-finish` (draft PR #2). Based on `3ed1890ae4ced76a42513f392d3b3b13a273cdd0`.

## Baseline evidence

Verified delivery run `34507312116`, placement job `102972561419`, pinned Godot `4.7.2.stable.official.ed1daf0bf` on Windows: import passed; vegetation integration passed 940 checks; movement/rotation passed 26 checks. The next gate, `m2_home_catalogue_test`, failed 1 of 45 checks: `expanded home options stay above the controller prompt bar`. Later rendering/export/delivery remained gated.

The previous multifloor layout layer only reduced button custom minimum heights to 27 and separation to zero. It did not bound the panel: the full VBox content minimum still propagated through MarginContainer and PanelContainer.

## Change

- Replace that compression workaround with a vertical ScrollContainer around the original VBox, after inherited panel construction has completed. Preserve the same buttons, order, callbacks and controller navigation. Use 42px minimum action heights without reducing font size.
- Bound panel height against the actual prompt-bar position and viewport, with a 12px gap. Recompute when the viewport, prompt rectangle or panel visibility changes.
- Follow controller focus, including wrapped navigation and reopened panels; keep ordinary scrollbar/touch support. Do not modify world input routing, building authority, automatic floor windows, geometry, palettes or shaders.
- Keep the existing catalogue regression unchanged. Add `m2_home_options_layout_test` to the existing placement gate: normal/smaller/larger windows, raised prompt bar, every enabled option in visual order, both wrap directions, focus visibility, cancel/reopen and unchanged world data/cursor.

## Verification at source handoff

The baseline CI logs above were read. The new changes have not yet run in Godot at commit creation; the new source must pass the pinned CI gates. Local engine tests and captures are **not run**: no Godot executable is installed in this session, and the local GitHub clone fails DNS resolution. Physical Thor/controller/touch testing is **not run**. No new APK, desktop package, screenshot, Drive upload or visual approval is claimed. Keep PR #2 draft and unmerged until required checks and approval are recorded.

Next: inspect the pushed commit's placement result, then the unchanged dependent render/export/package-verification gates. Record any later failure separately rather than weakening the gates or expanding repair scope silently.
