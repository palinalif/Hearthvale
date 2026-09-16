# Placement Test Maintenance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring stale placement/browser tests in line with the current controller-first build browser and harden native test execution so assertion failures cannot become misleading runtime errors or long CI stalls.

**Architecture:** Keep gameplay/runtime code unchanged. Update tests to drive stable player-facing inputs and browser item IDs instead of retired catalogue internals, add prerequisite guards where tests currently dereference data after a failed check, and give each native Godot invocation a bounded process timeout while preserving live logs and receipt validation.

**Tech Stack:** Godot 4.7.2 / GDScript, PowerShell 7, GitHub Actions Windows 2022.

**Spec:** `tasks/M2-hamlet-building.md`

## Global Constraints

- Preserve controller-only gameplay, authoritative saves, undo/redo, placement semantics, and existing test coverage.
- Do not weaken or remove assertions to obtain green CI.
- Do not change gameplay/runtime behavior unless a test demonstrates an actual product defect.
- Keep commits small and independently reviewable.

---

### Task 1: Rewrite stale browser/catalogue tests

**Files:**
- Modify: `tests/m2_build_browser_test.gd`
- Modify: `tests/m2_home_catalogue_test.gd`
- Test: placement `catalogue-behavior` and the native shard containing `m2_home_catalogue_test.gd`

**Interfaces:**
- Consumes: current `BuildBrowser` category/item metadata and controller input routes.
- Produces: tests that assert current player-facing browser modes, item IDs, placement previews, material choices, and cancellation/authority behavior.

- [ ] Capture the existing failing catalogue-behavior CI as the RED baseline.
- [ ] Read the current browser implementation and identify the intended world and house category sets plus stable item IDs.
- [ ] Rewrite stale assertions/navigation around those current contracts; remove references to retired `_build_catalogue_*`, `_roads_catalogue_*`, `_hamlet_catalogue_*`, and `_home_catalogue_*` internals.
- [ ] Run the affected catalogue/native shards and verify green without touching gameplay code.
- [ ] Commit the browser-test repair.

### Task 2: Harden test prerequisite failures

**Files:**
- Modify: `tests/m2_hamlet_detail_state_test.gd`
- Modify: `tests/m2_attachment_preview_test.gd`
- Modify: `tests/m2_attachment_boundary_test.gd`
- Modify: `tests/m2_furniture_placement_test.gd`

**Interfaces:**
- Consumes: existing `_check`/`check` assertion counters and native test receipts.
- Produces: clean assertion exits when prerequisites are absent, with no unchecked array/node dereference after a recorded failure.

- [ ] Add a focused test/fixture or minimal deliberate failure mode where practical to prove the guard catches the missing prerequisite.
- [ ] Add early-return/continue guards after prerequisite assertions before indexing arrays or dereferencing nodes.
- [ ] Replace `preview_cells >= 0` with a real furniture-preview invariant (`preview_cells > 0` or another current non-vacuous presentation contract validated from production behavior).
- [ ] Run native-placement/native-ui affected shards and verify green.
- [ ] Commit the guard cleanup.

### Task 3: Add a per-native-test watchdog

**Files:**
- Modify: `tools/test-m1-placement.ps1`
- Test: placement native shards plus a PowerShell-level watchdog regression if an existing harness is available.

**Interfaces:**
- Consumes: `$editor`, per-test argument arrays, live console output, and existing receipt/error-pattern checks.
- Produces: `Invoke-Gate` that streams stdout/stderr, captures output for receipt parsing, preserves real exit codes, and terminates a single Godot invocation after a bounded timeout instead of consuming the entire shard timeout.

- [ ] Establish the current no-timeout behavior from source and the previous hanging CI evidence as RED.
- [ ] Rework `Invoke-Gate` to launch Godot with redirected output that is streamed/tail-read while the process runs.
- [ ] Apply a generous per-invocation timeout (120 seconds for native tests; a separate larger import timeout if needed) and kill the process tree on expiry.
- [ ] Preserve `ERROR:/Parse Error:/FAIL:` detection and successful receipt checks exactly.
- [ ] Run the native-placement shard and at least one additional native placement shard to verify ordinary tests remain unaffected.
- [ ] Commit the watchdog.

### Task 4: Final integration verification

**Files:**
- No new implementation files expected.

**Interfaces:**
- Consumes: commits from Tasks 1–3.
- Produces: exact-head CI evidence suitable for merge.

- [ ] Verify branch is a clean descendant of current `main`.
- [ ] Run/inspect exact-head placement CI, including `placement-native-placement`, `placement-catalogue-behavior`, and the relevant native UI/catalogue shard.
- [ ] Record any unrelated baseline failures separately; do not weaken tests to make the whole repository green.
- [ ] If affected gates are green, fast-forward or merge to `main` without force and verify the resulting ref.
