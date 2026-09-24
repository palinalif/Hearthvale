# Hearthvale — project rules

## Authority and scope

Hearthvale is a personal cozy voxel town-builder for AYN Thor Max. The user directs art, design and playtest acceptance; agents implement, test and report evidence. M1 is complete and M2 is active under `tasks/M2-hamlet-building.md`. The user's current request and new acceptance decisions override older plans; do not invent scope.

Start with `HANDOFF.md`, the active task/ticket and the user's current request. Read inherited M1 contracts or relevant design docs only when needed. Do not load historical reports or the whole repository by default.

## Stable project facts

- The current default world is the M2 starter valley. Do not diagnose performance from stale dense-forest APKs or old generated worlds; verify the running build/package and current world first.
- Preserve existing user/test checkpoints and saves. Never uninstall an app or discard saves to solve deployment or signing problems.

## Non-negotiable contracts

- Preserve native volumetric terrain, caves/overhangs, controller-only gameplay on one gameplay screen, continuous sculpting, resize/detail editing, attachment recovery, undo/redo, duplication and save compatibility. Never replace terrain with a heightmap/static substitute. Gameplay requires no online model.
- Standalone presentation assets such as props, furniture and miniatures are authored as MagicaVoxel voxel assets. Stretchable/variable-dimension elements such as windows, doors, shutters and trims may remain procedural.
- Authoritative records are separate from generated meshes. Stable IDs, manual overrides, suppressions and recoverable invalid attachments survive regeneration. Reject stale async results.
- Menus block world input. Cancel restores previews; disconnect/focus loss stops held brushes. Each committed edit is one undo transaction.
- Native terrain and authoritative structure remain on the `0.125` grid. Decorative presentation may use `0.0625` cells. Preserve structural dimensions, anchors, collision, placement records and save authority; refine assets by adding/removing cells, not stretching cells.
- Town to City guides architecture/garden composition; Station to Station guides landscape/vegetation and fine miniatures; Tiny Glade guides building interaction. Use actual references and comparable Godot Mobile captures. Avoid noisy textures, oversized cubes, smooth low-poly substitution and photorealism.

## Working style

Implement ordinary work directly. Do not use subagents/workers/delegation unless the user explicitly requests it; if requested, use at most one narrowly scoped worker with minimal relevant context and clear ownership/acceptance checks.

Treat the session todo list as the authoritative short-term work plan. When the user approves or requests work, add/update a todo before implementation. Mark the active item `in_progress`, mark verified/completed work `completed` promptly, and create new items for approved follow-ups rather than silently widening an existing task. For substantial work, put the agreed implementation plan, constraints and acceptance checks in the todo description so they survive compaction.

Use small reviewable commits and one writer per subsystem. Read/search narrowly, bound tool output and store large logs on disk. Reuse unchanged evidence, prefer targeted checks during iteration, and avoid narrating unchanged polling. For long-running jobs use bounded waits/timeouts and check no more often than necessary. Prefer `bg_task` (spawn with `notifyOnExit: true` and a real `timeoutSeconds`) over blocking foreground bash or manual polling: start the job, continue independent work, and handle the result when woken, keeping the matching todo item in_progress until verified. Never edit files that a running job consumes unless it runs from an isolated worktree/snapshot. Batch independent read-only calls in one turn.

While the Godot MCP editor owns the checkout, prefer its editor-aware tools for Godot-owned files. Use `script_edit` for targeted changes to existing scripts and `script_write` for new scripts or deliberate whole-file rewrites; use the relevant MCP scene/resource/project tools when they cover the change. Use ordinary filesystem editing for non-Godot files such as Markdown, CI configuration, shell scripts and repository tooling.

Keep one writer per Godot file. Do not concurrently modify the same `.gd`, `.cs`, shader, scene, resource or project file through MCP, filesystem tools, shell commands or another editor. When switching writers, finish the current operation and re-read the current file/state before continuing. Do not launch a second persistent or editor-mode Godot instance against the same checkout while the MCP editor is active, including `--editor` / `--headless --editor`; use an isolated worktree/snapshot or stop the MCP editor first. Short-lived non-editor test/export commands may use the same checkout when they do not compete for file ownership.

Reason concisely and action-first. Do not repeatedly restate the task, known findings or plan. When the next useful tool call is clear, make it; reserve extended reasoning for genuinely ambiguous, architectural or high-risk decisions.

For commands that may keep running after a known fatal error (notably Godot/export/ADB composite jobs), use `tools/failfast --timeout <seconds> -- <command>` so fatal output returns control immediately. Use explicit longer timeouts for legitimate long builds; do not rely on the fallback timeout alone.

For headless SceneTree tests, call `tools/run-test tests/name_test.gd` (from any directory; default 600 s bound, override with `TEST_TIMEOUT_SECONDS`). It supplies the required `--script` and failfast handling. **Do not** use `godot --headless --path . res://tests/name_test.gd`: without `--script`, Godot runs the default gameplay scene indefinitely instead of the test. Rendering/capture tests need their own non-headless invocation.

## Architecture and Godot code quality

- Prefer composition and existing seams over extending the already-deep gameplay scene inheritance chain. Do not add another subclass merely to introduce one feature.
- Never copy a parent's multi-line implementation into a child. Call `super`, override the smallest seam, and keep shared setup in one owner.
- Give each piece of authoritative state one clear owner. Visuals, previews and caches are derived state, not competing authorities.
- Keep scene scripts focused on orchestration/input/integration. Put reusable calculations, validation and data transformations into small typed helpers that can be tested independently.
- Prefer typed GDScript and explicit references. Isolate dynamic `get`/`set`/`call`, string-based APIs and plugin reflection behind small adapters.
- Avoid per-frame whole-world polling, scans and unconditional rebuilds. Prefer events, revisions/dirty state and bounded incremental work.
- Keep input, authoritative state, save data and presentation separate. Preserve stable IDs and backward-compatible save schemas.
- Do not add Autoloads, global managers, abstraction layers or frameworks for speculative future needs. Refactor only around concrete ownership, coupling or duplication problems.
- Test the smallest useful layer and observable behavior rather than implementation shape.

## Critical recurring gotchas

- The pinned Zylann voxel extension is gitignored and required for terrain. Before Android export, verify `addons/zylann.voxel/` is installed from `dependencies.lock.json`. After export, verify exactly one matching ARM64 `libvoxel*` exists in the APK. A missing extension can produce a successful, bootable export with no voxel terrain.
- The live gameplay scene uses a very deep script inheritance chain. A parse/import error low in the chain can cascade into many misleading class-resolution errors; fix the first/root import error before debugging dependent failures.
- The Godot MCP/editor is development-only. If the live analyzer rejects an API, treat that as evidence the API is invalid; verify replacements rather than guessing.
- The Godot MCP/editor and external tools must not compete as writers. Prefer MCP edits while the MCP editor owns the checkout; do not modify the same Godot file concurrently through external tools, and do not run a second editor-mode Godot instance against the same project directory. If a workflow genuinely needs another editor instance, stop the MCP editor first or use an isolated worktree/snapshot. Unsaved built-in-editor changes are not authoritative once an agent writes that file.

## Verification and delivery

CI workflows run explicit test lists, not every test. For landscape/water changes, run the relevant local suites and register new tests where required; "CI green" alone is not sufficient evidence.

Tests should assert observable behavior and invariants rather than incidental exact counts, exact node-tree shapes or other brittle implementation details. Prefer relationships/ranges unless equality itself is the contract.

Every significant gameplay, visual, content, interaction or delivery-pipeline change must be committed and pushed as the exact tested source and must produce a valid verified ARM64 APK before handoff. Do not treat local-only work, an unverified export or an unpushed commit as delivered.

Handoff must state actual tests/failures, versions, artifacts and remaining work. Desktop evidence is not Thor evidence; unavailable checks are reported as not run. Visual approval belongs to the user.

## Thor and device testing

On-device evidence uses the existing debug-only virtual-controller bridge and spec-driven harness. Prefer semantic setup actions plus real InputMap/controller events for interaction. All ADB/device operations must use bounded timeouts.

Do not assume a running app is the build you intended: verify package/version/install success when results are surprising. Preserve installed user/test apps and signing identity rather than uninstalling to work around deployment issues.

Close the game between unattended/performance test rounds and return to the configured screensaver so the Thor can cool and avoid OLED burn-in. Do not treat thermally throttled runs as valid performance evidence.

Keep current device address/port, package/version, active performance findings and one-off bridge diagnostics in `HANDOFF.md` or the todo list, not here.

## Godot API verification

When working with Godot APIs:

- Do not invent or infer API names from memory when uncertain.
- If the live Godot analyzer/LSP rejects an API, treat that as authoritative evidence that the proposed call is invalid.
- Before replacing a rejected API, verify it using one of:
  1. Godot MCP / live ClassDB or GDScript analyzer
  2. Official Godot documentation
  3. A minimal standalone Godot probe
- Prefer `OS.has_feature("...")` for Godot runtime feature tags.
- Never modify project code based only on a guessed API.
