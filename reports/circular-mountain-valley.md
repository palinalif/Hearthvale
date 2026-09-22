# Circular mountain valley — v77

Based on main `81297b180ec24acc111d4d2dfb65ecb9e0c56737`; branch `fix/circular-mountain-valley`.

New worlds have an irregular circular basin, raised native foothills and three substantial surrounding mountain layers. The northern reservoir sits at 23 m and feeds an 18 m waterfall into the 5 m river. The downstream outlet remains open. Native terrain, caves, sculpting and the 0.125 m grid remain intact.

The fresh starter layout now matches the already-doubled terrain pads and river, without stretching houses or props. Existing checkpoints keep their terrain, water and building records. The starter scene now calls the inherited checkpoint initialization. Mountain face winding/normals and waterfall material/shading issues were corrected.

## Verification

Godot 4.7.2.stable.official.ed1daf0bf; pinned Voxel extension v1.7x.

Passed local checks:
- valley_ring_occlusion_test: 3,830 checks, zero failures (native boundary, real mesh winding, skyline and outlet).
- premade_river_test: 50 checks, zero failures (water budget, reservoir, supported cliff and river landing).
- waterfall_test: 20 checks; waterfall_visual_test: 7 checks; zero failures.
- m2_starter_valley_test: zero failures (composition, voxel preservation, deterministic materials and ponds).
- m2_starter_scene_test: 26 checks, zero failures (native cliff, home support, starter water, save/reload).
- m2_starter_migration_test: zero failures (supported previous 640-cell/v4 format, cave/overhang preservation, no reseeding, original checkpoint bytes retained).
- sculpt_test: 188 checks; water_visual_test: 16 checks; water_excavation_test: 8 checks; zero failures.

The old migration test still targeted 512-cell/v3 after the main branch changed its supported previous format to 640-cell/v4. The fixture now follows the declared previous-format contract; this change does not add a v3 migration path. The localized-water test now drains bounded multi-frame work before checking the result, rather than assuming the whole job fits into one 6 ms pass.

Mobile render capture: passed, nine 1280x720 captures from the production scene, including full-world native mesh readiness and a real border dig. Final overview and waterfall images were visually inspected. Desktop Intel Iris Xe evidence only; Thor performance/controller tests were not run. Visual acceptance remains with the user.

## APK

`org.hearthvale.game.test.m2night`, versionCode 77, versionName `2.0.1-m2night-v77`. Signed with the existing local debug key. Verified signature, Mobile renderer, package/version, compiled starter scene, ARM64-only architecture and exactly one voxel library matching the pinned dependency. Development resources are excluded.

SHA-256: `a4eb55c312f247a1532f17671e5db6b68dd5f75b2dfc680bb0aef20c3a91fc99`.

Start a new world to see the new generated basin and source cliff. Existing saved terrain is deliberately preserved. No device installation or save deletion was performed.
