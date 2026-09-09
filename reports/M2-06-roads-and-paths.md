# M2-06 — Roads & Paths evidence

Implemented on `feat/m2-hamlet-building` on 2026-09-09.

## Automated evidence

- Pinned Godot 4.7.2 import: pass.
- `tests/m2_path_state_test.gd`: 18 checks, 0 failures.
- `tests/m2_path_placement_test.gd`: 30 checks, 0 failures.
- `tests/m2_path_render_test.gd` headless: 14 checks, 0 failures.
- `tests/m2_path_render_test.gd` actual Mobile/D3D12: 16 checks, 0 failures.
- `tests/m2_home_catalogue_test.gd`: 38 checks, 0 failures.
- `tools/test-m1-placement.ps1`: pass.
- `tools/check.ps1`: pass.

## Actual render

The pinned Godot 4.7.2 console editor was run with Forward Mobile and D3D12:

```text
Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method mobile --rendering-driver d3d12 --audio-driver Dummy --max-fps 30 --script tests/m2_path_render_test.gd
```

The fixture placed packed earth, cobblestone, and stepping stones into the
existing hamlet scene, checked finite/grounded/bounded geometry, and captured:

[m2-paths/all-styles.png](screenshots/m2-paths/all-styles.png)

The reviewed capture shows the three styles as distinct blocky authored forms:
continuous packed earth, course-based cobblestone, and separated stepping
stones. The renderer batches each style independently and remains presentation-
only over the native voxel surface.

This is desktop Mobile renderer evidence, not physical Thor performance or
controller approval.

## Delivery

Source commit `822ffaa6620436240e9dc22ba720869527c98be4` passed verified
delivery run `34404866082`:

- all prerequisite gameplay and render jobs passed;
- the isolated ARM64 APK was exported and verified;
- the Windows x86-64 playtest ZIP was exported, launched, and verified;
- both artifacts and their verification receipts were uploaded to private
  Google Drive.

[GitHub delivery run 34404866082](https://github.com/palinalif/Hearthvale/actions/runs/34404866082)
