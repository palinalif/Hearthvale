# Hearthvale — start the next M1 chat here

Updated 2026-09-07. Repository: `E:\Voxel Game Project\Hearthvale` (PowerShell/Windows). This is an existing playable Godot game, not the original planning ZIP. **The user will supply new changes they want before considering M1 complete. Treat those as the next task; do not invent or begin M2.** Read this and AGENTS.md, inspect git status, then read only the relevant ticket/design/code sections. Do not replay the old chat or rerun unchanged baseline tests just to resume.

## Authority and working style

M1 is one genuinely editable procedural cottage plus continuous sculpting and a modest riverbank scene. Tickets: `tasks/M1-editable-cottage.md`, `tasks/M1-terrain-sculpting.md`, `tasks/M1-playtest-iteration-2.md`. Preserve all ticket regressions and unresolved M0 evidence. No villagers or catalogue expansion. Current status is **review candidate, not M1 complete or visually approved**.

User strongly values usage efficiency: Astra/medium main, Astra owns actual visual implementation, one Luna/low worker for bounded routine nonvisual work when worthwhile, Terra/medium only when deeper review is justified. No inherited worker history or child agents; targeted checks, compact outputs and reused evidence. Project defaults are in ignored `.codex/config.toml`; `.codex/agents/luna_worker.toml` is tracked. Existing task/UI settings may override defaults. Prefer Standard speed when conserving allowance. See `docs/agent-efficiency.md` only for setup details.

## Current playable baseline

- Last game implementation: commits `9c67551` (fine terrain/migration), `b1173dc` (miniature cottage/planting); evidence `378e6f9`. Workflow-only changes follow, including `8738c75`; inspect current HEAD for the latest preparation commit.
- APK: `builds/hearthvale-m1-iteration2-debug.apk`, version **5 / 0.1.2-m1-garden**, package `org.hearthvale.game`. SHA256 `0138d46cf80982154a25da499c9796dcdae9157718095482091cdd46b8c5393e`. Windows debug alongside it. Earlier APK/saves preserved; do not overwrite either.
- Godot **4.7.2.stable.official.ed1daf0bf**, matching templates, Voxel Tools GDExtension **v1.7x**, commit `75d3c6d996ed2331c80edcd8c3ebc947afc0f041`. Exact archives/hashes: `dependencies.lock.json`. Mobile renderer. Pinned editor under `.tools/godot-4.7.2/`.
- All visible asset and native terrain steps now use **.125 world units**. Terrain384×256×384 retains48×32×48 world bounds; legacy .5 terrain is exactly upsampled, keeping old shapes/caves/files. Raw terrain72MiB/generation. Decorative geometry is separate from simulation.
- Fresh cottage scale.25; an existing save retains its transform until controller **Cottage → Miniature scale**. Automatically reflowed windows, optional shutters, manual shutters/flower boxes, recoverable attachments, resizing, duplication and history persist.
- Sculpt strength6 (previous1.5), quarter-rate precision, fixed Level target and advancing brush preview. Terrain menu has Foliage brush, Tree brush, Clear planting. Seeded trees/plants/rocks are saved; actual terrain changes remove affected roots, undo restores both layers.

## Read only what the requested change touches

| Area | Primary files |
|---|---|
| Controller, menus, scene integration/history | `scripts/m1_scene.gd` |
| Sculpting, migration, native data | `scripts/terrain_backend.gd`, `scripts/m1_patch_generator.gd`, `scripts/checkpoint_store.gd` |
| Editable cottage records/layout | `scripts/building_world.gd` |
| Actual visual geometry | `scripts/cottage_visual.gd`, `scripts/vegetation_mesh.gd`, `scripts/visual_grid.gd` |
| Saved planting/presentation | `scripts/landscape_state.gd`, `scripts/m1_garden_visual.gd` |

Relevant tests have matching names under `tests/`. Use `tools/iteration.ps1 -Plan` to inspect the consolidated workflow and `docs/build-and-test.md` for usage. Run targeted checks while editing; run the complete required gates once stable. The full acceptance write-fixture already performs the entire scenario; its separate cold-read follows without duplicating the first run.

## Reusable evidence and remaining gaps

`reports/M1-playtest-iteration-2.md` records actual passes, failed attempts and fixes. Baseline: sculpt188; resolution/migration46+cold11; planting32+cold6; checkpoint47; scaled backend29; targeted planting9; M1 controller; full cottage acceptance112+cold8. Actual Mobile grid87,608 checks passed. APK structure/signature/native library and exported Windows startup passed. The original aggregate stopped on failures; corrected targeted reruns passed—do not misrepresent this as an uninterrupted aggregate pass.

Desktop RTX3070 short sculpt profile16.73ms median/19.43ms p95; forced repeated resize rebuild31.44/37.29ms. These are **not Thor measurements**. Latest build physical install/controls/performance/thermals/interrupted saves remain not run unless the user now provides evidence. Prior user playtests approved neither these latest changes nor M1 completion. Native per-edit mesh completion acknowledgement is unavailable.

Art references: `docs/references/rulebook/index.html` and its `images/`. Town to City for architecture/gardens, Station to Station for landscape/vegetation/miniatures; Tiny Glade for interaction. Inspect actual images when doing art. Latest captures: `reports/screenshots/m1-iteration2-final.png`, `m1-iteration2-close-final.png`, `m1-iteration2-edited-final.png`. Palette review was requested; broad plain ground, regular roof courses and simplified crowns remain visual gaps. User's upcoming feedback decides priorities.

MCP3.2.5 remains isolated; earlier open-script overwrite persistence check failed (`docs/mcp-smoke.md`). Don't claim a new pass. Google Drive uploads are authorized; previous build was not uploaded because the old session lacked tools. Drive plugin is now listed in the app; verify current callable upload tools/destination before using it, without making files public. No device was attached at the last check; inspect fresh only when device work is needed.

Preparation validation: the new runner passed PowerShell parsing, read-only All-plan/order checks, invalid/empty target rejection, forced timeout with the dependent test marked not_run, and a real import + nine-check plant-target run. Logs: `reports/logs/iteration-workflow-smoke-20260907/receipt.json` and `iteration-workflow-timeout-20260907/receipt.json`. Its Capture/Export/All routes were inspected/planned, not newly executed end to end; use them for the next changed candidate rather than claiming old evidence validates the wrapper.

This preparation changes workflow/docs only; it does not rebuild the APK or resolve gameplay/visual/Thor gates. Start by reconciling the user's newly supplied changes with the authoritative M1 ticket, preserve useful work, then implement within that scope.
