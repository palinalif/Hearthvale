# Small Luna tree-variation trial

Status: isolated trial implemented and independently checked; awaiting player visual feedback. The player explicitly asked Luna for a small test of variations on the existing tree while playtesting M1. No production integration, replacement APK, or new asset catalogue is implied.

## Delegation evidence

Codex CLI 0.153.1 and the existing luna_worker definition were inspected. The worker was spawned explicitly with model gpt-5.6-luna and reasoning high. A read-only delegation completed successfully: it read the project policy and tree generator, viewed local official reference screenshots and the current Hearthvale capture, and ran the pinned Godot version check (4.7.2.stable.official.ed1daf0bf). Independent runtime model metadata is not exposed; configuration is not reported as independent runtime verification.

The test correctly identified existing canopy spacing 0.24 versus cube edge 0.255 (6.25% overlap inflation). For this isolated experiment all tree cells, including trunks and branches, must be cubic with 0.24-world-unit edges and grid spacing. This trial value does not select the eventual project-wide visual unit or normalize the existing cottage.

AGENTS.md and the existing Luna configuration now record this explicit bounded exception to Astra ownership. No model cache or permissions were changed. Luna owns new dev/tree_variations files and its dedicated screenshots; the lead owns shared policy, task decomposition, independent checks and this report.

## Requested comparison

Three variations of the current broadleaf tree: compact/spreading, tall/upright, asymmetric/wind-swept. Keep the established sage/olive palette. Produce differing shapes through cell occupancy, not scaled cubes. Actual Mobile review views must include the current procedural cottage for scale, with normal and close captures, image inspection and revision. Tests must cover deterministic generation, differing silhouettes, cell dimensions after complete transforms, grid alignment, support connectivity and bounded geometry/draw groups.

References: rulebook station-to-station-00 and -04, town-to-city-02, and m1-astra-final.png. This is a controlled production experiment; borrowed reference subjects do not authorize railways, extra buildings or tree species.

## Isolation

Before assignment, the user's playtest APK SHA-256 was fd1c2f342355c22f9e39641b1f73ac6be4b85586ab0ad623302d2fe8bf2e9423. Runtime exports already exclude dev/*. No game code, checkpoints or build artifacts are assigned for change.

## Review results

Luna authored the generator, test script and review scene. The lead requested revisions after inspecting the first renders: fix reversed Z-face normals, replace the large right-angle branch with connected diagonal steps, broaden crown lobes, and replace scattered color noise with coherent regions. The lead subsequently corrected oversized review labels and camera framing only, then rendered and inspected both final views. Existing before captures are retained; framing changed, so they are qualitative comparisons, not pixel-aligned comparisons.

Independent headless validation on the pinned Godot executable passed **43 checks, zero failures** (`reports/logs/tree-trial-lead-test.log`). Checks include deterministic occupancy, distinct variants, cubic mesh geometry after complete transforms, grid alignment, connected wood, normal/winding consistency, and rejection of a stretched parent. Commands are in the [trial README](../dev/tree_variations/README.md).

| Variant | Cells | Bounds in world units (X/Y/Z) | Material groups |
|---|---:|---|---:|
| Compact/spreading | 535 | 4.56 / 3.84 / 2.88 | 4 |
| Tall/upright | 498 | 3.36 / 5.76 / 2.16 | 4 |
| Asymmetric/wind-swept | 552 | 5.04 / 5.28 / 2.40 | 4 |

Final [normal](screenshots/tree-trial/normal-after.png) and [close](screenshots/tree-trial/close-after.png) captures succeeded at 1280×720 in actual Vulkan Mobile on the desktop RTX 3070, with no final capture errors. The close view deliberately focuses on the trees and crops the cottage; the normal view includes the complete cottage. Before views: [normal](screenshots/tree-trial/normal-before.png), [close](screenshots/tree-trial/close-before.png).

Visual assessment: three clearly different silhouettes and consistent cell dimensions are demonstrated. The tall crown still reads as stacked lobes; the leaning variant is exaggerated, and shaded foliage loses some stepped detail. Labels remain small. These are exploratory variants, not approved production vegetation or proof of matching the full reference quality. Further crown blending and subtler asymmetry should follow player selection. Existing cottage voxel dimensions are not normalized by this experiment.

Physical Thor checks and performance measurements: **not run**. Full game regressions: **not rerun**, because production code is untouched. No claim of M1 completion or visual approval. The current playtest APK remains unchanged.


## Integration finding during implementation

The initial worker test attempted MultiMesh transform readback under the headless dummy renderer. Lead investigation confirmed that the pinned Godot 4.7.2 dummy mesh storage implements per-instance transform setters as no-ops and returns identity from the getter: [pinned source](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/servers/rendering/dummy/storage/mesh_storage.h), lines 173 and 182. The final implementation instead uses ArrayMeshes, whose CPU-side vertices allow meaningful headless geometry checks. Actual appearance was separately checked in Mobile. Earlier captures also exposed a camera look-at call before entering the tree; this was fixed. Several worker capture attempts exited without saving images and are not counted as successful evidence.
