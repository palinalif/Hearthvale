# Build and test Hearthvale

Run PowerShell from the repository root (`Hearthvale`). The pinned runtime is project-local; do not use the existing Godot 4.2.2 Mono installation.

## Consolidated iteration command

Use a new descriptive `-Name` each run; the runner refuses existing output names. Inspect its plan without running tools or creating files:

```powershell
./tools/iteration.ps1 -Stage All -Name m1-next -Plan
# During development: import and only the affected tests.
./tools/iteration.ps1 -Stage Targeted -Tests tests/plant_target_test.gd -Name planting-fix-1
# Stable candidate: full checks once, actual Mobile geometry, three clean
# captures, versioned Android/Windows debug exports and APK verification.
./tools/iteration.ps1 -Stage All -Name m1-next
```

`Check` (default) runs the existing headless suite, including import. `Capture` runs import, actual Mobile visual-grid validation and normal/close/edited captures. `Export` runs import, both Mobile debug exports and APK verification. `Targeted` requires explicit existing test paths. The non-All modes are partial gates, not completed milestone evidence. Review captures manually; a successful export does not establish Android gameplay.

Full logs and a stage receipt are written under `reports/logs/iteration-<Name>/`; debug exports go under `builds/iteration-<Name>/`. Dependent stages stop at the first failed/timeout/error result. Receipt fields distinguish attempted and omitted checks; no mode approves visuals or claims Thor testing. Before a new distributable version, update the version code/name in `export_presets.cfg` deliberately and preserve the signing identity. Drive upload remains a separate connected-tool action without embedded credentials.

The lower-level commands below remain available for individual diagnosis and legacy Compatibility exports. Do not additionally run them after equivalent unchanged gates already pass through the consolidated command.

Prerequisites: Windows x64, PowerShell 7, Java 17, Android SDK, and Python/uv only for the optional MCP sandbox. This host uses Temurin 17.0.19+10 and Android build-tools 36.0.0. Godot's Android SDK/JDK editor settings must point to the installed directories. Do not commit personal paths, keystores, credentials, or `.godot` caches.

## Engine and project

Run `tools/bootstrap.ps1` to download the locked archives, validate their hashes, and restore the project-local editor, Android/Windows templates, native extension, and optional MCP sandbox addon. `-SkipDownloads` requires the existing cache. Existing dependency files that differ from their locked archive are rejected instead of overwritten. The MCP server itself is started separately using the tagged setup in `mcp-smoke.md`.

```powershell
./tools/bootstrap.ps1
$godot = '.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --editor --import --quit
& $godot --path . --disable-vsync --max-fps 60
```

The game uses Mobile by default. The explicit desktop launch flags avoid the poor VSync pacing observed on this host; they do not change the APK's default display settings. For the same fixture with Compatibility:

```powershell
& $godot --path . --rendering-method gl_compatibility --disable-vsync --max-fps 60
```

M1 is the current implementation milestone. Its controller route is in `M1-controller-and-review.md`; its evidence and remaining device checks are in `../reports/M1-editable-cottage.md`. The retained M0 scene can be launched explicitly with `--scene res://scenes/m0.tscn`. The internal application name remains unchanged to preserve the existing desktop user-data directory. M1 uses a separate checkpoint root and never overwrites M0 player checkpoints.

## Native probe and tests

For the M0 placement follow-up, the terrain tool shows a live affected-cell preview. Use small left-stick nudges for fine placement, D-pad up/down for height, and left/right for radius. X switches ADD/REMOVE. A locks the target; orbit and zoom to inspect it, then A commits or B cancels. Cancel before repositioning a locked target. The preview is a display aid and does not change terrain until confirmation.

```powershell
./tools/check.ps1
# Individual diagnostic checks:
& $godot --headless --path . res://probes/dependency_probe.tscn -- --probe
& $godot --headless --max-fps 60 --path . --script tests/backend_test.gd
& $godot --headless --max-fps 60 --path . --script tests/controller_test.gd
& $godot --headless --max-fps 60 --path . --script tests/building_world_test.gd
& $godot --headless --max-fps 60 --path . --script tests/sculpt_test.gd
& $godot --headless --max-fps 60 --path . --script tests/m1_controller_test.gd
& $godot --headless --max-fps 60 --path . --script tests/m1_acceptance_test.gd
& $godot --headless --max-fps 60 --path . --script tests/m1_checkpoint_test.gd
& $godot --headless --path . --script tests/checkpoint_test.gd
& $godot --headless --path . --script tests/checkpoint_test.gd -- --write-fixture
& $godot --headless --path . --script tests/checkpoint_test.gd -- --read-fixture
& $godot --headless --path . --script tests/checkpoint_test.gd -- --write-second
& $godot --headless --path . --script tests/checkpoint_test.gd -- --read-second
```

Native terrain loading uses worker threads. Tests wait against a wallclock deadline; a fast headless frame count alone is not a loading timeout. Review logs for script errors even if a process exits zero. Test roots must remain separate from player checkpoints.

## Android exports

```powershell
./tools/build.ps1 -Windows -Compatibility
```

This produces debug and release-mode Android APKs, plus Windows executables when `-Windows` is supplied. Existing release signing environment variables take precedence. Otherwise the script uses an existing local development keystore, sets signing variables only for its process, and restores prior values afterward. It never creates or commits a key. On this host the Godot development keystore supplies both modes; the final signature comparison is recorded in the report.

`-Compatibility` also exports a Compatibility debug APK (and a Compatibility Windows release executable with `-Windows`). Use `-CompatibilityOnly` to rebuild only these variants. Windows uses the `m0_compatibility` export feature and Godot's documented [feature-tag settings](https://docs.godotengine.org/en/stable/tutorials/export/feature_tags.html).

Android also needs export-time renderer settings so its manifest declares OpenGL. Keep the editor closed and do not edit project configuration during an export. The script backs up the exact `project.godot` bytes, temporarily sets its base and mobile renderer values to Compatibility, then restores the original bytes in `finally`. It refuses an existing `override.cfg` or backup. Concurrent edits or an interrupted process leave `.tools/project.godot.compatibility.backup` for inspection and recovery; compare it with the project before restoring it, and never discard concurrent work. The lead verified both the final manifest's `gl_compatibility` value and byte-for-byte restoration.

The APK retains the application ID and development signing identity so the device can compare renderers as updates without erasing saves. Verify the renderer shown by the debug overlay after each installation.

The default Android debug identity is for personal sideload testing, not production distribution. Preserve it outside source control to retain update compatibility. The stable application ID is `org.hearthvale.game`; both modes use the same identity on this host. Export presets include ARM64 only. Verify signatures with your SDK's `apksigner verify` and inspect the archive for the respective native voxel `.so`. The MCP sandbox and reference artwork must not be in either APK.

Install only on an authorised attached device: `adb install -r builds/hearthvale-m1-iteration2-debug.apk`. This command was not run while no Thor was connected. Do not uninstall an existing app or erase its saves to work around signing errors. Iteration 2 uses Android version code 5, version name `0.1.2-m1-garden`, with the same package ID and signing identity as M0. The preceding v4 APK is retained separately.

## Verified Google Drive delivery

`.github/workflows/m1-drive-delivery.yml` is the single delivery gate. Every branch push triggers it; concurrent older runs for the same branch are cancelled so only the newest commit can reach delivery. It calls the sculpt-feedback, Terrain UX, placement and cottage/Mobile workflows, downloads the isolated APK only after all four succeed, revalidates its verification receipt, and then asks the private Apps Script webhook to copy the same immutable GitHub artifact to Drive. Tag pushes are excluded. The workflow resolves GitHub's authenticated artifact endpoint to a short-lived signed URL immediately before notifying Apps Script; GitHub credentials are not sent to Google. The Apps Script contract reuses an identical same-name Drive file and rejects conflicting bytes or non-private output.

GitHub Actions cannot reuse the Codex desktop Google Drive connection. Deploy the repository-specific Apps Script `doPost(e)` receiver with `WEBHOOK_SECRET` and `DRIVE_FOLDER_ID` script properties. Add its deployment URL and matching secret as encrypted repository secrets, then enable delivery:

```powershell
gh secret set APPS_SCRIPT_WEBHOOK_URL
gh secret set APPS_SCRIPT_WEBHOOK_SECRET
gh variable set GOOGLE_DRIVE_UPLOAD_ENABLED --body true
```

The webhook accepts only a JSON `secret` and HTTPS `download_url`, downloads the artifact ZIP, and admits only its APK and JSON receipt. Keep the URL, shared secret and script properties out of Git, logs and artifacts. Until the switch is exactly `true`, the final Drive job is visibly skipped while all test/build jobs still run. The workflow runs automatically for `master` pushes and can also be dispatched manually for an explicitly selected ref. Its current Apps Script download ceiling is 50 MiB; the workflow rejects a larger artifact before notifying it.

For a versioned iteration-2 debug export, preserving the previous playtest file:

```powershell
./tools/check.ps1 -TimeoutMs 240000
& $godot --headless --path . --export-debug 'Android ARM64' builds/hearthvale-m1-iteration2-debug.apk
& $godot --headless --path . --export-debug 'Windows' builds/hearthvale-m1-iteration2-debug.exe
python tools/verify-m1-apks.py --apk builds/hearthvale-m1-iteration2-debug.apk --report reports/m1-iteration2-apk-verification.json
& $godot --path . --script res://tests/visual_grid_test.gd -- --require-rendering
```

Check full export logs for script errors as well as exit codes. The actual Mobile geometry test is additional to the headless suite: headless MultiMesh transform readback is unavailable and is reported as unverified. Fine terrain uses .125-unit cells in the same world bounds; old terrain is exactly upsampled, preserving its existing shape and legacy files. Each new raw terrain generation is 72 MiB. Saved cottages retain their transform until the undoable Cottage → Miniature scale action.

## Retained M0 renderer fixture

```powershell
& $godot --path . --scene res://scenes/m0.tscn --rendering-method mobile --disable-vsync --max-fps 60 -- --benchmark --benchmark-seconds=60
& $godot --path . --scene res://scenes/m0.tscn --rendering-method gl_compatibility --disable-vsync --max-fps 60 -- --benchmark --benchmark-seconds=60
```

Benchmark JSON is written under the game's user-data directory, named by renderer. Benchmark writes use a test checkpoint root. The measured frame intervals include editing and saving; the cycle cost includes edit, undo, redo, and checkpoint writing. VSync and the frame cap must be recorded: this host showed substantially different pacing with VSync enabled. Desktop results do not establish Android performance, sustained thermals, native GPU memory, or controller feel. Use the same fixture and settings on the Thor before comparing.

In the retained M0 scene, open Start → Run 60s fixture. It saves dirty player data first, uses a fresh private benchmark backend, and shows the result with Return to valley and Quit choices. These measurements cover the M0 fixture, not the denser M1 terrain and cottage. Record default Thor VSync/display settings separately from the explicit desktop CLI settings above.


## Reproduce the Astra M1 review

From the project root, `./tools/check.ps1` runs the full regressions. `./tools/capture-m1.ps1 -View cottage -Clean -Name my-normal` renders the actual Mobile scene in an isolated review world. Use `-View close -Clean -Edited -Front -Name my-edited` for a resized cottage with a moved window. These captures hide HUD/debug; they are not performance measurements.

For a bounded desktop profile, run the pinned Godot executable with `--path . --disable-vsync --max-fps 60 --script res://tools/m1_visual_profile.gd`. The script uses a separate temporary save root. Compare results only under the recorded renderer/resolution and distinguish desktop from Thor.

Build with `./tools/build.ps1 -Windows -Compatibility`, then verify APKs with `python tools/verify-m1-apks.py` (requires the recorded SDK/JDK and archived first M1 APK for signing continuity). Read `reports/M1-visual-rework.md` for actual results, limitations, captures and device checklist. `tools/*` is excluded from runtime exports along with MCP and other development resources.
