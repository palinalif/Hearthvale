# HANDOFF-pi.md — branch pickup state (recorded by Pi, 2026-09-17)

Resume artifact for the three feature branches. Per-branch durable state lives in
each branch's `notes.md` (read it FIRST before touching that branch).

## Verified remote state at pickup

| Branch | Tip | Feature state |
|---|---|---|
| `task/house-wall-details` | `2da78ba` | Complete: Trim_ brick coursing + plaster mottle, tests green, CI detail-grid contract fixed |
| `task/living-grass` | `80726f5` | Part 1 done (deterministic meadow tone field); **part 2 (auto-scattered tufts) never started** |
| `task/house-landing` | `9c4817c` | Tuft ring + dirt rim + test locks pushed |

## Findings (discrepancy vs. the outgoing handoff)

- PRs #21 (wall-details), #22 (living-grass), #23 (house-landing) were found
  **closed, not merged** (`merged: false`). The user confirms they were NOT
  closed on purpose — likely collateral from the billing-death run or a stale
  remote state. They cannot be merged as-is because:
- All three were based on `master @ 6ae02f9`, and **`master` no longer exists
  on the remote**. Default branch is `main`; at pickup `origin/main = 5ee2155`,
  ~180 commits / ~13.7k inserted lines ahead of `6ae02f9`, including
  `c11a5aa` "green CI test maintenance" which likely resolves the two
  pre-existing test failures those branches noted (cottage_detail_render_test
  repeat-stability + m2_hamlet_composition_render_test `path.points` crash) and
  much of the Windows-host CI failure family the branch tips carried.
- Consequence: each branch must be **rebased onto `origin/main`, re-verified,
  re-pushed, and its PR reopened with base = `main`**.

## Plan / status as of this commit

1. [x] Record this handoff (this file).
2. [ ] Rebase `task/house-wall-details` onto `origin/main`; headless verify;
      force-push; reopen PR #21 with base `main`.
3. [ ] Rebase `task/living-grass` onto `origin/main`; headless verify;
      force-push; reopen PR #22 with base `main`; **then implement part 2
      (deterministic auto-scattered tufts)** per `tasks/` + notes.md.
4. [ ] Rebase `task/house-landing` onto `origin/main`; headless verify;
      force-push; reopen PR #23 with base `main` (picks up the two
      previously-stuck commits `5dad921`, `9c4817c`).
5. [ ] CI gates each rebased branch to green on `main`; user visual approval;
      merge order is up to the user (wall-details → grass → landing is the
      natural dependency order if any overlap appears).

## Local environment notes

- Godot 4.7.2 headless available at `godot`; **no Xvfb in this sandbox**, so
  render-gate legs rely on CI.
- Local `main` working tree carries unrelated uncommitted WIP (BACKLOG.md
  IDEA-008 + `docs/proposals/` + untracked `.uid` files) — left untouched.
