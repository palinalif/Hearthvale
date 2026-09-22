# Starter Valley Art Pass — plan & status

Goal (user request 2026-09-21): turn the M2 starter valley into a materially larger, attractive,
believable old-European-inspired landscape — buildings/roads following contours, dense irregular
settlement, water, forest, elevation; no visible skybox/floating boundary; cozy storybook feel in
Hearthvale's voxel language. References = attached images (mood, not literal layout).

Execution: sequential single-agent stages (heavy overlap — no parallel implementation agents),
one writer per subsystem, small reviewable commits. Visual evidence via on-device Thor
screenshots (local headless has no renderer — `valley_screenshot.png` is a white box).
Note: several subagent sessions died silently on a stale-extension-ctx harness bug;
mechanical changes were done inline when a worker went dark.

## Stage 1 — read-only audit (DONE, explorer agent)

Key findings:
- World is 640×256×640 native (0.125 m voxels, 80×64×80 m), 2-byte/voxel ≈ 1 GB voxel data.
  128 m extent would be ~4× that — risky on the 2.5 GiB Thor → keep 640³, reshape the feel.
- Terrain is nearly flat: ±0.9 m variation around level 0.075, center kept flat for the hamlet.
- Presentation ring: 56 m radius, 2 m max, procedural only. Sky is a procedural gradient +
  dither pattern (m2_valley_sky, m1_sky, m1_skybox — M2 uses m2_valley_sky).
- Vegetation: 56 trees (5 kinds) in a fixed ring band + 27 bushes near the edge; water is a
  56-radius circular lake.
- Paths: M2 path authority (painted path regions, excavation) + M1 path system.
- Editing: M2 section edit (brush sculpt), M2 terrain paint, M2 world bounds; M1 terrain paint
  tools with brush/eraser.
- Save: composition, homes, path cells, planting; migration path from M1.

## Stage 2 — Valley composition & environment (DONE)

Landed on `main` (8224de0): new `m2_valley_surround.gd` ring (56 m peak band, irregular peaks,
~70 m outer wall, 640×256×640 volume), updated valley/scene tests (640 vs 512),
`f7e02c9 WIP: starter valley overhaul (recovered from main working tree)` carrying the M2 files.

Repo-state note (learned the hard way, 2026-09-22): a **parallel pi session** was working the same
goal — it created `task/starter-valley-art-pass` (worktree `.pi/art-pass`), retired `master`,
switched the main checkout, and committed the valley-ring work to `main` (8224de0, == origin/main).
**`main` is the active line.** Never work in `.pi/art-pass` from this session. My initial
worktree (`.worktrees/valley-artpass`, branch `main`) lost its uncommitted agent work when the
branch moved — removed. Stage 2 visual captures remain in /tmp/valley_artpass_s2_after_*.png:
mountain ring fills the rim view; lake + tributary + green visible from the high pose.
Remaining cosmetic gap: at the *highest* reachable camera pose the ring can read low — Stage 3/5
polish should keep rim coverage in mind (PEAK_HEIGHT=56 vs max target_y≈59.6).

## Stage 3 — Ground variation + player terrain paint (DONE; bevel reverted)

Landed as `6bbda22` (layered paint, palette, tests). The beveled-cube model from that stage
tiled 45-degree chamfer faces into a chevron pattern across flat ground on the Thor, and the
olive DENSE/DRY tints pulled the meadow off the green family — both reverted in `8a52ed4`;
plain cubes and green tints remain, approved patch variety kept.

## Stage 4 — Village art pass (IN PROGRESS)

Landed so far: `a3d7902` ponds and shoreline (two deterministic organic lakes, water 7.5 m /
bed 6.75 m, idempotent re-carve guard, tests green; pre-existing m1_landscape_test failure is
unrelated). Remaining per below:

- Grow the settlement toward the reference mood: denser, irregular, contour-following;
  stone/timber/plaster mix, steep roofs, small tower/clock-tower landmark, tavern/inn,
  gathering places, warm lamps, street furniture, market details.
- New MagicaVoxel assets as needed (staged under .tools/magicavoxel, promoted on review).
- All new buildings on the 0.125 structural grid; props on 0.0625.
- Composition: keep the starter scene small enough to load fast and readable from the default
  camera; growth must stay within the valley center plateau.

## Stage 5 — Polish & verification (not started)

- Lighting/mood pass (warm interior lights, lamp glow), foliage variety, water shimmer polish.
- Full test suite (explicit list), headless captures at several poses (incl. rim view).
- APK export + on-device verification on the Thor when the device is back online.
- Final user visual acceptance.

## Rules for every stage
- One writer per subsystem; small reviewable commits; commit+push before handoff.
- Verify Zylann extension present before export; APK must contain exactly one ARM64 libvoxel.
- Device ops bounded; preserve saves; close the game between unattended runs.
- Kill/avoid the live Godot MCP editor before build work (it can revert .gd edits).
