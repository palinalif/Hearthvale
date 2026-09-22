# Terrain-colored detailed mountains - v78

Follow-up on `fix/circular-mountain-valley`, after v77 (`fed6980`). The mountain faces now have branching ribs, gullies, broken ledges and small crest crags. All three ranges use the exact native GrassTone shader palette, with darker vertex tints at higher elevations instead of blue-grey rock.

The nearest mountain shoulder has real axis-aligned exposed voxel tops and risers on the native 0.125 m lattice. Two-cell height steps and merged coplanar faces keep this narrow transition affordable; an irregular outer edge meets the continuous face underneath. The shoulder is cached once. It is derived boundary scenery with no collision/save/edit authority; playable terrain remains the native volumetric terrain, including caves, edits and checkpoint data. These scenery changes apply to existing worlds without resetting them.

## Verification

- `valley_ring_occlusion_test`: 715,702 checks, zero failures. Includes native boundary/river outlet, crest variation, all-layer winding, closed noise seam, finite geometry, voxel-grid alignment, outward voxel faces, mesh budgets and shared native palette.
- `premade_river_test`: 50 checks, zero failures.
- Production Mobile capture: 11 images, zero failed checks, full native-world meshing and a real border edit. Overview, voxel transition and waterfall visually inspected. Captures in `reports/screenshots/detailed-mountains/`.
- Static smooth ranges: 30,272 triangles. Cached voxel shoulder: 128,638 triangles. No per-frame generation or animation added.
- Prior v77 native save/migration/sculpt/water suites were not rerun: their production sources are unchanged. Desktop Intel Iris Xe captures are not Thor performance evidence; Thor installation/controller/performance checks were not run. User visual acceptance remains outstanding.
- The Windows capture wrapper initially could not share-read its redirected error log; the game ran and completed successfully with an empty error log and a passing receipt. The export wrapper uses shared log reading.

## Android artifact

Package `org.hearthvale.game.test.m2night`, versionCode 78, versionName `2.0.1-m2night-v78`. Existing debug signing identity. Verified v2/v3 signature, Mobile renderer, ARM64-only architecture, compiled mountain script, development-resource exclusion and exactly one ARM64 voxel library matching the installed pinned dependency. AAPT reports the existing template's missing themed-icon resource; package and signature checks pass.

APK size: 40,227,486 bytes. SHA-256: `a328830c23c7732e5a78307c94afbd7a332b126dd03902cf2c60dd4dc74accfd`.

The verified APK and source-hash receipt are delivered in the task outputs; the exact source revision is added to the receipt after commit/push verification.
