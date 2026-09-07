# M1 feedback: smoothing candidate

2026-09-07. First isolated fix from the player's latest M1 feedback. Review branch: `fix/m1-sculpt-feedback`. This is not M1 completion or visual/device approval.

## Changed

- Cache the connected native surface, footprint and influence during a stroke. Surface searches occur on cache misses instead of on every fixed tick.
- Replace each column's 25-neighbour dictionary loop with brush-local summed-area statistics. Reuse target statistics until the footprint or a cached surface changes.
- Read a halo outside the write footprint so the brush boundary does not bias the neighbourhood mean.
- Use a half-cell rounding threshold and signed, resettable residuals instead of repeatedly changing a whole voxel for a 0.05-cell error.
- Retire a front when removal exposes a void, rather than retargeting a disconnected cave floor. Native volumetric data, history and save formats are retained.
- Avoid allocating native edit buffers for fractional input or settled surfaces.

## Evidence and validation

An independent Python numerical check of the summed-area formula matched a naive average for 11,300 seeded neighbourhood cases, including missing columns and different kernel radii. This checks the mathematics, not the Godot implementation or device performance.

New executable Godot tests: `tests/smooth_neighbourhood_test.gd` and `tests/sculpt_smoothing_test.gd`. Cover mean equivalence, slope halo, missing columns, stationary surface-query reuse, spike settling/no chatter, cancel/undo/redo, 30/60-fps held input and a disconnected cave floor.

The accompanying GitHub Actions workflow uses the existing locked Windows editor and voxel extension with hash checks and no signing keys. It runs import, both new tests, the existing sculpt regression and the scaled backend regression. Consult the run for this exact commit; configuring the workflow does not establish a pass. The editing container has no Godot runtime and its direct GitHub clone/download attempts failed. Native tests were not run in that container.

Not established by this patch: physical Thor frame times, moving/max-radius smoothing comfort, visual approval, exported APK, full M1 integration/checkpoint/controller gates. Measure those before merging/releasing.

## Remaining feedback

The approved miniature scale stays unchanged. Raise/dig brush shapes, wall-locked furniture ghosts/free placement, free cottage duplication, hover/A/X detail editing and recolouring, tree silhouettes and the river are separate fixes and are not claimed as implemented here. Existing foliage/tree brush behaviour is preserved.
