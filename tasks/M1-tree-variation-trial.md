# M1 small Luna tree-variation trial

Explicitly requested by the player while playtesting 0.1.1-m1-rework. This is an asset-production workflow test, not catalogue expansion or a replacement APK.

Deliver three recognizable variations of the current broadleaf tree: compact/spreading, tall/upright, and asymmetric/leaning. Keep a coherent palette and connected foliage masses with fine stepped silhouettes. Use the existing tree as the starting reference, not three unrelated species. Use one 0.24-world-unit cubic cell size for this isolated trial, including voxelized trunks/branches. This trial value reuses the existing canopy grid spacing; unlike the existing tree, cube edges must equal that spacing, without the 0.015 overlap. Do not scale cells to change tree size. The eventual global visual unit remains a separate integration decision.

Inspect actual images: rulebook station-to-station-00 (branch tiers and small foliage), station-to-station-04 (tree/building relationship), town-to-city-02 (planting composition), and reports/screenshots/m1-astra-final.png (current benchmark). Do not borrow railway content, elaborate buildings, or blurred presentation as a substitute for readable geometry.

Implementation ownership: only dev/tree_variations/** and reports/screenshots/tree-trial/**. Use a disposable actual Godot Mobile review scene showing all three trees together beside the existing procedural cottage for scale. Preserve the production scene, scripts, checkpoints, editor/MCP state and APK. Reuse existing palette/lighting conventions. Add deterministic generation and checks for cubic size/grid spacing through complete transforms, bounded draw calls/cell counts, distinct silhouettes and connected woody support. Render normal and close views, inspect, describe the largest gaps and revise at least once. Record commands and final seed/cell counts.

The lead independently checks the output. A worker completion or test pass is not visual approval. No physical Thor claim follows from this desktop trial.
