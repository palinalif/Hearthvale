# Build and test M0

Run PowerShell from the repository root (`Hearthvale`). The pinned runtime is project-local; do not use the existing Godot 4.2.2 Mono installation.

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

## Native probe and tests

For the M0 placement follow-up, the terrain tool shows a live affected-cell preview. Use small left-stick nudges for fine placement, D-pad up/down for height, and left/right for radius. X switches ADD/REMOVE. A locks the target; orbit and zoom to inspect it, then A commits or B cancels. Cancel before repositioning a locked target. The preview is a display aid and does not change terrain until confirmation.

```powershell
./tools/check.ps1
# Individual diagnostic checks:
& $godot --headless --path . res://probes/dependency_probe.tscn -- --probe
& $godot --headless --max-fps 60 --path . --script tests/backend_test.gd
& $godot --headless --max-fps 60 --path . --script tests/controller_test.gd
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

Install only on an authorised attached device: `adb install -r builds/hearthvale-m0-debug.apk`. This command was not run while no Thor was connected. Do not uninstall an existing app or erase its saves to work around signing errors.

## Renderer fixture

```powershell
& $godot --path . --rendering-method mobile --disable-vsync --max-fps 60 -- --benchmark --benchmark-seconds=60
& $godot --path . --rendering-method gl_compatibility --disable-vsync --max-fps 60 -- --benchmark --benchmark-seconds=60
```

Benchmark JSON is written under the game's user-data directory, named by renderer. Benchmark writes use a test checkpoint root. The measured frame intervals include editing and saving; the cycle cost includes edit, undo, redo, and checkpoint writing. VSync and the frame cap must be recorded: this host showed substantially different pacing with VSync enabled. Desktop results do not establish Android performance, sustained thermals, native GPU memory, or controller feel. Use the same fixture and settings on the Thor before comparing.

On a controller, open Start → Run 60s fixture. The game saves dirty player data first, uses a fresh private benchmark backend, and shows the result with Return to valley and Quit choices. This gives the Thor a repeatable route without an external keyboard. Record its default VSync/display settings separately from the explicit desktop CLI settings above.
