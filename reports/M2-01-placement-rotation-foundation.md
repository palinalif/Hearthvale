# M2-01 placement and rotation foundation

Implemented on `feat/m2-hamlet-building` from the accepted M1 baseline.

## Result

New-home duplication and existing-home relocation now share a pure transform preview with controller yaw adjustment. D-pad left/right rotates by 15 degrees normally or one degree in precision/free mode; D-pad up toggles rotation snapping and L3 toggles precision. The ghost, footprint and committed transform use the same candidate transform.

World-bound and oriented-footprint overlap checks run continuously. Invalid confirmation remains in preview and displays a plain-language reason. Valid duplication deep-copies building, surface and attachment identities in one transaction. Existing-home movement/rotation commits the same record atomically and preserves its local authored data. Both paths reject stale source revisions.

This slice deliberately reuses the existing cottage. It does not yet add the residential catalogue, additional recipes, foundation terrain responses, planting effects or the ticket's final status icon treatment.

## Evidence

- `tests/m2_placement_rotation_test.gd`: 26 checks, 0 failures.
- Inherited `m1_building_placement_test.gd`: 16 checks, 0 failures.
- Inherited `m1_house_actions_test.gd`: 50 checks, 0 failures.
- `tools/test-m1-placement.ps1`: complete pinned placement/asset/landscape/controller/UI suite passed, including the new M2 gate.
- Actual Forward Mobile / D3D12 render: 389 checks, 0 failures on NVIDIA RTX 3070. This is desktop Mobile-render evidence, not Thor performance or player approval.
- `reports/screenshots/m2-placement-rotation/rotated-home-preview.png`: valid rotated ghost with visible controller grammar.
- `reports/screenshots/m2-placement-rotation/invalid-overlap.png`: invalid overlap with visible reason text.

An ARM64 APK and physical Thor review remain separate delivery evidence.
