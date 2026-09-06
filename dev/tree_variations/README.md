# Luna tree variation experiment

Isolated development scene; not integrated into the game or Android export. Luna authored the generator and tests. The lead reviewed renders, ran independent checks, and corrected final review labels/framing.

From the project root, run:

```powershell
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://dev/tree_variations/tree_variation_test.gd
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe --path . --scene res://dev/tree_variations/tree_variation_review.tscn
```

Append `-- --capture=normal-after` or `-- --capture=close-after` to render and exit. Captures are written under `reports/screenshots/tree-trial/`; use the real Mobile renderer, not headless capture.

`TreeVariation.build_variant(kind, seed)` returns an unscaled Node3D. Supported kinds: `compact`, `tall`, `asymmetric`. Every foliage and wood cell has a 0.24 world-unit cubic edge. This experimental value does not establish the eventual global visual unit; the comparison cottage is existing production geometry and is not normalized by this test.

At seed 1042 the variants contain 535, 498 and 552 cells respectively, with four material groups each. Larger silhouettes use more cells, never stretched cells. The generator emits static ArrayMeshes with coherent foliage color regions. Surface cells retain cube faces; this is not a final optimized vegetation pipeline.

See [trial report](../../reports/M1-tree-variation-trial.md) for review limitations and evidence. The normal view includes the full existing cottage for scale; the close view prioritizes the trees and crops part of the cottage.
