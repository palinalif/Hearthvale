# Visual finish resumes — lighting and palette comparison

2026-09-11: the player authorizes moving from UX into visual polish. Bring the parked PR #4 study onto verified master 461a5da4 without reverting any house/section/window/shutter controls. The bottom-half catalogue remains separate in PR #10: its focused Mobile tests passed, but delivery run 34553496813 still has a failed placement-render timeout even though the parallel cottage job succeeded. Do not merge or call that build delivered as part of this art task.

## First visual slice

Compare four looks on the actual current gameplay scene: baseline, directional sky fill with the existing sun, lower warm-daylight sun/sky, and that same warm look with the quieter meadow albedo #82935e (current ground is #7d9957). Normal, close, reverse and genuinely edited upper-floor views yield sixteen images. Each look uses identical camera framing, geometry, exposure, tonemapper and frozen wind. No bloom, fog, blur, remeshed assets, external assets or scene-size expansion.

The reusable VisualLightingProfile applies a private Environment. Its sky mode controls ProceduralSkyMaterial sky/ground energy: Environment.ambient_light_energy cannot dim a 100% sky contribution. The ground-colour variant only changes the runtime-created grass material in the disposable comparison scene, then restores it. It does not change terrain cells or the generator's default palette. Baseline is retained as the comparison and restore path.

The rendered test checks actual 1280x720 Mobile output, fixed framing/exposure, unchanged building/landscape records for every look, effective ground-colour pixel differences, and source restoration. The edited fixture uses the existing add-floor API; an unchanged static cottage is not substituted. A manifest identifies exact source, engine and capture parameters. Separate profile tests check resource isolation and atomic invalid-input rejection.

## Delivery boundary

Review-only: no live gameplay default or scene rewiring yet. Do not claim that an automatically exported APK enables a candidate profile. The existing full delivery workflow is untouched; the dedicated study requires all sixteen images. Pick an art direction using those comparisons, then enable the accepted profile in a separately verified gameplay change. Next art priorities remain architectural relief/roof courses, contact shading, ground/path/bank integration and restrained water. The miniature scales, personal colours and controller editing are non-negotiable.

At source preparation, source/API inspection only; there is no local Godot executable and a live git network probe failed DNS. Exact-head native and Mobile evidence is pending. Exposed lead is GPT-6 Astra Pro, not the repository's requested Sol; no model switch or subagent is used. No physical Thor result, aesthetic approval, new playtest package or master merge is claimed by this report.

Primary API references checked 2026-09-11:
- https://docs.godotengine.org/en/stable/classes/class_environment.html — sky contribution and ambient energy scope.
- https://docs.godotengine.org/en/stable/classes/class_proceduralskymaterial.html — effective sky and ground energy multipliers.
- https://voxel-tools.readthedocs.io/en/latest/api/VoxelBlockyLibrary/ and https://voxel-tools.readthedocs.io/en/latest/api/VoxelBlockyModel/ — native scene-library material access.

Reference direction: the player's Town to City images (especially the normal gameplay overview) and docs/design.md section 3. Reference pixels are not copied into albedos or redistributed as game assets.
