# 2026-10-04 (glow round) — `feat/m2-glow`: emissive lantern + interior window glow, on a clean branch off main

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

