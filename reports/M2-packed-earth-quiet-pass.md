# Packed earth: quiet soil, real terrain edges

## Scope and baseline

Player-authorized experiment, 12 September 2026. Based on the actual current
`feat/m2-path-ground-polish` head `7473cd8bf37452fb87f50f63713303fc48bb4764`
("Use faceted packed-earth wear silhouette"), not the older summary head.
Original helper Git blob: `c180b57884bb8e462e0a0305e5a02b669dfb66f4`.
Candidate helper Git blob: `dc2cc353c167b3636365713439665e369a17cf26`.

This is a review candidate, NOT a visually accepted or verified APK delivery.
The active path-polish branch, stone paths, saves, native terrain, dependencies,
workflow gates and test thresholds are unchanged. No junction redesign is included.

## Changes

- Emit only the two dirt bands. Remove the two green-painted shoulder bands;
  the actual native terrain is now visible immediately beyond the dirt edge.
- Remove green endpoint tint and the world-space colour ripple. Preserve the
  existing geometric endpoint taper and top-only native-height clipping.
- Keep broad route-relative facets but remove compulsory alternating deep
  notches and companion bites. Longer cells can have no bite; a selected bite
  is shallow and its side and location are independently seeded.
- Space broad compaction fields farther apart (8.4 and 11.6 world units instead
  of 5.2 and 7.1). Reduce the light field's blend from 0.30 to 0.18; use a subtle
  0.12 dark-field blend. No extra detail geometry, noise texture or draw pass.
- Interpolate the cross-path normal used for colour evaluation between stations.
- Place grass at the actual tapered dirt boundary, not the removed outer strip.
  Select fewer tufts and require at least 2.75 units between accepted groups.
  Existing cube size, central clearance, native-root checks and hard caps remain.

## Local evidence

The editing container has no direct GitHub network access and no Godot binary.
The connected GitHub API was used to inspect and publish the source. A local
copy of the original helper was verified against its exact Git blob SHA before
editing; the candidate must match the blob recorded above after publication.

A Python execution of translated scalar functions (NOT Godot execution) passed:

- Existing width-case scalar assertions at widths 0.25, 0.75 and 3.0, including
  the original edge bounds, continuity, asymmetry and sparse-wear thresholds.
- 216,540 core-boundary samples across 54 stable IDs, five widths and distances
  0 through 100. Every sampled core was finite and inside its safety envelope.
  The smallest sampled combined core width was 79.05% of nominal width, excluding
  the deliberately tapered endpoints. This is a sample result, not a proof.
- Uniform sampling of the two wear fields above strength 0.1 marked 29.59% of
  the old sampled area and 19.23% of the new area. This is a scalar estimate,
  not a pixel measurement or a visual acceptance claim.

Source comparisons confirmed `_height`, `_ground_polygon`, `mesh_from_builder`,
`stats` and `_faceted_profile` are byte-identical. The shared path renderer and
stone/contact implementation are not modified at all. No test was weakened.

## Required remaining evidence

Run the unchanged exact-head verified Drive workflow. Native/GDScript parsing,
mesh budgets, terrain contact, save/undo lifecycle, actual Mobile captures,
Android ARM64 verification, Windows packaging and private Drive delivery are
NOT claimed from the local scalar checks. Review the candidate's normal, close,
reverse and terrace path captures. Existing CI before fixtures refer to earlier
historic baselines, not automatically to this candidate's immediate parent.
Physical Thor/controller testing and the player's visual approval remain separate.
Do not merge or label this as delivered solely because the source was pushed.

Execution: the repository prefers Sol/high for visual work; this session exposes
GPT-6 Astra Pro. No model switch or delegation was performed.
