# 2026-10-05 — `feat/m2-vox-props`: authored voxel prop pipeline + a green glow gate

Head `4881ef6`, 15 commits ahead of `origin/main`, pushed, working tree clean.
Pinned engine: Godot `4.7.2.stable.official.ed1daf0bf` (`dependencies.lock.json`).

## What is on `feat/m2-vox-props`

- **Authored prop pipeline.** 54 `.vox` sources and 53 `asset.json` records, plus the staging
  tools `tools/magicavoxel/vox_to_obj.py`, `vox_to_asset.py`, `build_props.py`,
  `bake_furniture.sh` and `bake_mesh.gd`. Concept report in
  `reports/MagicaVoxel-prop-concepts.md`.
- **Lantern glow** as `scripts/m2_lantern_glow.gd`, tested by `tests/m2_lantern_glow_test.gd`.
- **Window glow is procedural, inside `scripts/cottage_visual.gd`** (window light nodes, no
  emission material). `tests/m2_window_glow_test.gd` tests that implementation. The standalone
  `scripts/m2_window_glow.gd` from the discarded `2ca8b70` branch was **not** landed: it calls a
  `M2CottageVisual.window_glow` / `window_glow_root` seam that does not exist here.
- **`ci-glow.yml` (`M2 glow`)** runs on push to this branch: install pinned editor + voxel lib →
  `--import` → five `--check-only` gates → parse the nine authored `.vox` sources to OBJ over a
  size floor → run `magicavoxel_asset_test`, `m2_lantern_glow_test`, `m2_window_glow_test`.

## Verified

- `M2 glow` **green** on `4881ef6` (run 37290860532, every step success). The job had never been
  green before; it took three stacked fixes — see "Glow CI" below.
- Whole job sequence reproduced green locally on a cold `.godot` cache: import 0, five check-only
  gates 0, three test scripts 0, nine `.vox` sources → OBJ over the floor.

## Not run / not delivered

- No APK export, no Thor device run, no actual-Mobile visual capture from this branch. Desktop
  headless evidence only; visual approval belongs to the user.
- The baked `.res` mesh library is **not** on this branch (`assets/runtime/meshes/` is empty).
  CI deliberately asserts the `.vox` sources, not baked artifacts.

## Glow CI — three stacked defects, all fixed

1. Voxel library installed as `template_release` instead of the editor build (`7eda4a7`).
2. `GODOT_EDITOR` was appended to `GITHUB_ENV` as a **bare path** with no `GODOT_EDITOR=`
   prefix, so the variable was never set (`4f7a232`).
3. `--check-only` ran **before** `--import`. Check-only resolves `class_name` identifiers from
   the project global class cache, which only exists after an import, so a fresh checkout always
   failed with `Identifier "M2LanternGlow" not declared`. Import-then-check-only is clean
   (`4f7a232`).

Also `4881ef6`: `tests/m2_starter_furniture_mesh_test.gd.uid` was the only tracked test script
with no committed `.uid`, so every fresh import regenerated an untracked one.

Two traps for whoever touches CI next:

- `gh run rerun` re-runs the **original** `head_sha`, not current HEAD. Reading a rerun looks
  like reading a fix and is not one.
- The job previously listed seven tests, four of which never existed (`cottage_visual_test`,
  `cottage_ward_visual_test`, `m2_composition_visual_test`, `m2_hamlet_visual_test`).

## Open: main CI is red, deliberately out of scope here

`Hearthvale verified Drive delivery` fails 28/30 jobs on `4881ef6`. `main` has failed since
Sept 17 (9 jobs), so this predates the branch, but the branch adds 21 newly-failing jobs. All 21
are `windows-2022` shards under `tools/test-m1-placement.ps1` / `tools/test-cottage-shard.ps1`.
GitHub's log endpoint returns empty for them; the shard scripts gate on `Invoke-MobileReview`,
which launches Godot with `--rendering-method mobile --rendering-driver d3d12` and requires a
render receipt. Untested hypothesis. The user is handling this in a separate session.

## Deferred from the `2ca8b70` harvest

- **Window-glow emission re-land** — needs a replace-vs-coexist decision on
  `scripts/cottage_visual.gd`'s procedural window lights, plus art acceptance. Medium.
- **`visual-glow.yml` + its three tests** — the workflow names `m2_hamlet_visual_test`,
  `m2_composition_visual_test`, `cottage_ward_visual_test`; none exist, and
  `scripts/cottage_ward_visual.gd` does not exist. Gated on the item above.
- **Naming** — nothing to do. `m2_` is this repo's existing convention (12 files on main) and
  `scripts/m2_hamlet_visual.gd` has no plural twin; the collision reported earlier was a
  misread.

---

# 2026-10-04 (glow round) — `feat/m2-glow`: emissive lantern + interior window glow, on a clean branch off main

> Historical. Describes `feat/m2-glow`, not the branch above. Its "What is on `feat/m2-glow`"
> file list (including a standalone `scripts/m2_window_glow.gd`) does **not** apply to
> `feat/m2-vox-props`.

## Why this branch exists

The earlier glow work lived on `feat/m2-lighting-polish`, which branched off `v80-main` and
dragged along ~100 commits of untested M1/M2 startup, terrain, water, mountain and CI work the
user has not tested on-device. The user asked to branch off main and reapply only the glow work.
`feat/m2-glow` is that: main `09111a1` + the glow commits, nothing else.

## What is on `feat/m2-glow`

- `scripts/m2_window_glow.gd` — interior lighting for cottage/bridge/shop windows.
  **12/12** in `tests/m2_window_glow_test.gd`.
- `scripts/m2_lantern_glow.gd` — applies the ember emissive to the **authored** lantern mesh
  (`hearthvale_prop_path_lantern.res`), which is the path the lantern actually takes.
  **6/6** in `tests/m2_lantern_glow_test.gd`.
- `scripts/visual_lighting_profile.gd` — Mobile-tier glow budget (3 lights per profile,
  12-light scene cap, distance culling, 100 ms re-evaluation).
- Glow checks are gated in their **own** CI job (`Source checks → Glow checks`,
  `tests/m2_window_glow_test.gd`, `tests/m2_lantern_glow_test.gd`), and the glow branch no
  longer triggers the GPU-only `Lighting polish study`.

## Two hard constraints found the hard way

1. **The lighting-polish CI gate is unsatisfiable on a normal branch.** `Lighting polish study`
   requires `godot-render-build` + `godot-render-ready` + `godot-render-visual` +
   `godot-render-visual-accepted`, which only a GPU capture can produce. A headless branch can
   never satisfy it. That is why glow lives in its own job.
2. **`tools/run-test` must be invoked as `tools/run-test tests/foo_test.gd` from the repo root.**
   Passing an absolute path makes Godot emit `res://tmp/...`, which resolves to the project's
   `scripts/` directory and fails with `Parse error: Cannot find class "M2StarterHamletVisual"`.

## MagicaVoxel pipeline facts (cost hours to discover; recorded so they are not rediscovered)

- **`tools/magicavoxel/bake_mesh.gd` takes user args after a `--` separator**:
  `godot --headless --path . -s res://tools/magicavoxel/bake_mesh.gd -- res://<stage>/x.obj res://assets/runtime/meshes/x.res`.
  Without `--`, `OS.get_cmdline_user_args()` is empty and it fails with its usage error.
- **Godot does not import assets under a dot-directory.** `.tools/glow/x.obj` never gets an
  `.obj.import`, so `load()` returns null and the bake fails with "could not load source mesh".
  Stage OBJs in `build/magicavoxel/` (gitignored and visible to the importer).
- **The OBJ material library is a shared global file**
  (`assets/runtime/materials/m2_prop_materials.material`): every bake merges into it and the
  manifest records only the last writer. Baking a prop whose OBJ material names collide with an
  existing entry silently rewrites the shared library. Names must be namespaced per prop.
- `emission_specular` is **not** a valid Godot 4 `StandardMaterial3D` property; the live analyzer
  rejects it. Emissive is set with `emission` + `emission_energy_ratio`.
- The Godot binary on this host is `/usr/local/bin/godot` (4.7.2). `/opt/godot/` is empty.

## Repository hazards (not caused by this session)

- `origin/main` is `09111a1`; `refs/heads/main` is `11111a1`. **`main` is not the integration
  branch** — `v80-main` is. Branching off `main` lands on a 2025-08-17 commit with no M2 code.
- `git worktree add` from a shell whose cwd is not the repo resolves relative paths against that
  shell's cwd, silently producing a worktree whose files are not the ones being edited. Use
  absolute paths everywhere in worktree workflows.

## Outstanding

- Furniture `.vox` → `.res` bake for bench/stone_bench/signpost/lamp_post/maypole/
  notice_board/water_pump/hay_cart/market_cross (sources exist, meshes did not).
- Wiring bench/lantern/signpost through `_authored_assets()` so the hamlet uses the authored
  meshes; the seam is generic (`has_style`, `mesh_for`, `VOXEL_COUNTS`, `PATHS`) so this is a
  helper module plus one registration line.
- No Thor device test, no APK from this branch, no user visual acceptance.

---

