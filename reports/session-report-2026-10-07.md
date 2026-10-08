# Hearthvale — session report, 2026-10-07

Self-contained handoff. Written for a reader with no access to the session transcript.

## Context

- **Project:** Hearthvale — personal cozy voxel town-builder for the AYN Thor Max (Android handheld).
- **Repo:** `palinalif/Hearthvale`, branch `main`. `origin/main` = `1114094`.
- **Engine:** Godot 4.7.2 (`/usr/local/bin/godot`), headless for parser checks and GDScript tests.
- **Milestone:** M1 complete, M2 (hamlet building) active under `tasks/M2-hamlet-building.md`.
- **Host limits:** no PowerShell, so `Hearthvale/tools/bootstrap.ps1` (Windows-only) cannot run. The
  pinned Zylann Voxel GDExtension is gitignored and must be installed manually before any local
  Android export, or the APK ships without `libvoxel` and voxel terrain silently fails to render.

## What was asked

1. Fix the CI pipeline on `main`, which had been failing for about two weeks.
2. Merge the voxel/props + glowy-lighting branch (`feat/m2-vox-props`) into `main`, re-run the tests,
   and produce an APK for playtest.
3. Separately: fix the `pi-background-tasks` Pi extension so a session shutdown stops killing
   background tasks.

## Delivered on `main`

Merge commits: `a196592` (CI fixes into main), `8fdd172` (`feat/m2-vox-props` into main).

Non-merge commits in this session's window, newest first:

| SHA | Change |
|---|---|
| `1114094` | fix(tests): gate captures on the orbit target, which is what the camera frames |
| `5d26de3` | fix(tests): centre the capture mesh gate on the camera, not the view axis |
| `c5ad742` | fix(tests): `patch_size` is cells, the clamps are metres |
| `bc44b83` | fix(tests): gate captures inside the viewer sphere, not outside it |
| `38d222a` | perf(test): gate starter captures on framed terrain, not the whole world |
| `160e257` | test(starter): report where the starter-valley shard spends its time |
| `8a56b0c` | test(roof): report where the joined-roof shard spends its time |
| `e359a15` | fix(ci): give the Windows terrain receipt a per-commit Drive name |
| `3bffa21` | test(joined-roof): clear the massing-shell memo, report a missing shell instead of crashing |
| `833a512` | ci: size the Mobile-review gates from measured cost, not guesswork |
| `18b82d7` | test(roof): invalidate the massing-shell memo when forcing a rebuild |
| `8f614e3` | ci: widen the Mobile-review gates for software-rendered runners |
| `4a5452c` | test(roof): report the roof nodes each pass produced |
| `9612c95` | test(planters): aim at terrain the scene reports instead of fixed coordinates |
| `f28d590` | test(roof): report per-case roof metrics |
| `2c655d6` | docs: record issue-triage policy and the current main snapshot |
| `6a5288e` | ci: size the test gates to measured startup cost |
| `295564b` | test(planters): report the placement reason a failed aim produced |

Root causes found and fixed along the way: stale 80 m world-size assertions, a native landscape
assertion, terrain-UX preview-live assertions, a planter placement home-overlap check, planter
catalogue selection, roof course instance counts, a camera-boundary fixture bound to an old map,
a Drive filename collision (`terrain-ready.json`), and a Drive-delivery APK package verification
step. The dominant CI cost was the `cottage-starter-valley` shard (1108 s, ~91 % of CI wall),
which spent ~1000 s meshing terrain no capture ever framed; the capture gate now keys on framed
terrain.

## APK for playtest

- **File:** `.tools/apk/main-e359a15a.apk` (40,369,868 bytes)
- **SHA-256:** `482507765ea6ef9d0c8af57faf5719f4775eb75bbfc9ece078a199c60c15e12b`
- **Package:** `org.hearthvale.game.repair.ce359a15a`, version `0.1.3-repair-e359a15a`, versionCode 6
- **Install semantics:** separate test app with fresh saves; does **not** replace `org.hearthvale.game`
- **Verified:** signature, metadata, ARM64 (`arm64-v8a`) only, mobile renderer, native voxel library
  matches the pinned `dependencies.lock.json` entry, repair scene compiled, development resources
  excluded. Produced by CI run `37501208517` (success).
- **Not verified:** physical Thor validation. No device run, no user visual acceptance.
- **Currency:** every commit after `e359a15` touches only `tests/` (3 files, +131/−19), so this APK
  is gameplay-identical to `main` tip.

## CI status — read this before trusting "green"

- **Last fully green run:** `37584483874` at `8a56b0c` (2026-10-07T06:58Z) — 42 jobs, all success.
- **Current tip `1114094`, run `37609840660`:** 38 success, **2 failure**, 2 skipped.

  1. `performance / mobile-performance-section-commit`
     Failing check: `full native valley meshes within 240000 ms` → measured **240317 ms** (0.13 %
     over). Runner is Windows with software rendering: idle median 2245 ms, ~0.45 fps, 174 k house
     meshes, 13 meshes, 176 k tris. The other 11 normalized fps/latency checks passed.
  2. `cottage-and-apk / cottage-starter-valley`
     Three capture labels error with `... frames meshed native terrain`: `reverse`, `edge-before`,
     `edge-edited` — the captures ran before native terrain meshed.

- **Cause of both:** test-side gating introduced in `38d222a..1114094`. The full-mesh budget check
  is new (added in `38d222a`) and is calibrated tighter than a software-rendered runner can meet;
  the capture gate is now tighter than the meshing stream can satisfy for the far-camera labels.
  Neither is evidence of a gameplay or rendering regression.
- **Open decision (not yet chosen by the player):** (a) widen `full_mesh_budget_ms` for
  software-rendered review runners and relax the three far-camera capture labels, (b) file these as
  durable CI/delivery issues first, or (c) leave them.

## pi-background-tasks extension fix (separate repo)

- **Repo:** `vanillagreencom/kendex`, package `pi-extensions/pi-background-tasks`.
- **Commit:** `6716c6b` — `fix(bg-tasks): a session shutdown no longer stops running tasks`.
  **Never pushed to `origin`.** The working clone under the repo's gitignored `.tools/` staging area
  has been deleted at the player's request; the only surviving copies are the git bundle and the
  `format-patch` file archived at `/root/bg-tasks-fix-2026-10-07/`. The player downloaded and
  installed the fix from the commit.
- **Behavior change:** `session_shutdown` previously SIGTERM'd then SIGKILL'd every running task, so
  watchers, builds, test suites and training runs died when a Pi session closed. Tasks spawn detached
  in their own process group, so they already outlive Pi. Shutdown now sends no signal and no unit
  call, sets no status and stamps no reason; it persists live tasks as `running` with their recorded
  pid + start time, releases only this session's timers, watcher, widget and output readers, and
  drops only wakes this session can no longer deliver. `session_start` rehydrates them as `running`
  and re-arms each running task's remaining `timeoutSeconds` deadline, so a deadline that elapsed
  while Pi was down fires at startup. Explicit `stop`, a reached deadline, a child close, and the
  liveness watcher's pid-gone / pid-reused verdicts are unchanged.
- **Tests:** full suite **109 pass, 2 skip, 0 fail** (111 tests) vs a pre-change baseline of
  100 pass, 2 skip. New `tests/shutdown-survival.test.ts` covers survival across restart, deadline
  re-armed before/after restart, elapsed deadline, pid gone, and pid reuse with and without a
  start-time identity check, plus a mutation must-fail that breaks when the shutdown kill is
  re-inserted. The shutdown rows of the stop/shutdown integration table were rewritten for the new
  contract.
- **Evidence limit:** the tests use the repo's end-to-end fixture harness (real extension code, real
  `session_shutdown` / `session_start`, real timers and wakes, simulated process layer). No real
  OS-level test (spawn a process, kill Pi, restart, inspect `bg_status`) was run.
- **Not installed:** live sessions on this host still run published 2.2.0. Version was not bumped;
  the changelog entry sits under `### Unreleased` per the repo's release convention.

## Outstanding

1. Player decision on the two red CI jobs above.
2. Thor device playtest and visual acceptance of `main-e359a15a.apk` — player-owned.
3. Push / PR decision for the extension commit `6716c6b` — it exists only as the archived bundle and
   patch at `/root/bg-tasks-fix-2026-10-07/`.
4. Furniture `.vox` → `.res` bakes for bench, stone_bench, signpost, lamp_post, maypole,
   notice_board, water_pump, hay_cart, market_cross (sources exist, meshes do not), and wiring them
   through `_authored_assets()`.
5. `HANDOFF.md` is stale in two respects: it describes `main` as a non-integration branch pointing at
   a 2025-08-17 commit with `v80-main` as integration (no longer true — `main` is the integration
   branch at `1114094`), and it predates this session's CI work.

## Reproduction notes for the next agent

- `tools/run-test` must be invoked as `tools/run-test tests/foo_test.gd` from the repo root; an
  absolute path makes Godot emit `res://tmp/...`, which resolves to `scripts/` and fails with a
  misleading `Cannot find class` parse error.
- A parse error low in the deep gameplay script chain cascades into many misleading class-resolution
  errors; fix the root import error first.
- The long-running headless Godot MCP editor can silently revert an externally edited `.gd` file to
  its stale in-memory copy. Re-grep edited scripts immediately before committing, and kill the editor
  process tree before on-device build work.
- CI workflows run explicit test lists, not every test; "CI green" alone is not sufficient evidence
  for landscape/water changes.
- Local Godot checks are fast-loop evidence only; they do not replace CI, actual mobile rendering,
  APK verification, or player visual acceptance.
