# Build and test M0

Run PowerShell from the repository root (`Hearthvale`). The pinned runtime is project-local; do not use the existing Godot 4.2.2 Mono installation.

Prerequisites: Windows x64, PowerShell 7, Java 17, Android SDK, and Python/uv only for the optional MCP sandbox. This host uses Temurin 17.0.19+10 and Android build-tools 36.0.0. Godot's Android SDK/JDK editor settings must point to the installed directories. Do not commit personal paths, keystores, credentials, or `.godot` caches.

## Engine and project

Restore the archives specified by `dependencies.lock.json` into `.tools/downloads`, validating their recorded hashes. Extract the official Windows editor into `.tools/godot-4.7.2`, the template files `android_debug.apk`, `android_release.apk`, `windows_debug_x86_64.exe`, and `windows_release_x86_64.exe` into `.tools/templates`, and the Voxel Tools archive's `addons/zylann.voxel` into `addons`. Automated bootstrap/build/check scripts are in `tools` once integration is complete.

```powershell
$godot = '.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --editor --import --quit
& $godot --path .
```

The game uses Mobile by default. For the same fixture with Compatibility:

```powershell
& $godot --path . --rendering-method gl_compatibility
```

## Native probe and tests

```powershell
& $godot --headless --path . res://probes/dependency_probe.tscn -- --probe
& $godot --headless --max-fps 60 --path . --script tests/backend_test.gd
& $godot --headless --max-fps 60 --path . --script tests/controller_test.gd
& $godot --headless --path . --script tests/checkpoint_test.gd
& $godot --headless --path . --script tests/checkpoint_test.gd -- --write-fixture
& $godot --headless --path . --script tests/checkpoint_test.gd -- --read-fixture
```

Native terrain loading uses worker threads. Tests wait against a wallclock deadline; a fast headless frame count alone is not a loading timeout. Review logs for script errors even if a process exits zero. Test roots must remain separate from player checkpoints.

## Android exports

```powershell
& $godot --headless --path . --export-debug 'Android ARM64' builds/hearthvale-m0-debug.apk
# Release-mode native-library test signed with this machine's development identity:
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = Join-Path $env:APPDATA 'Godot\keystores\debug.keystore'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = 'androiddebugkey'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = 'android'
& $godot --headless --path . --export-release 'Android ARM64' builds/hearthvale-m0-release.apk
Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH,Env:GODOT_ANDROID_KEYSTORE_RELEASE_USER,Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
```

The default Android debug identity is for personal sideload testing, not production distribution. Preserve it outside source control to retain update compatibility. The stable application ID is `org.hearthvale.game`; both modes use the same identity on this host. Export presets include ARM64 only. Verify signatures with your SDK's `apksigner verify` and inspect the archive for the respective native voxel `.so`. The MCP sandbox and reference artwork must not be in either APK.

Install only on an authorised attached device: `adb install -r builds/hearthvale-m0-debug.apk`. This command was not run while no Thor was connected. Do not uninstall an existing app or erase its saves to work around signing errors.

## Renderer fixture

```powershell
& $godot --path . --rendering-method mobile -- --benchmark --benchmark-seconds=60
& $godot --path . --rendering-method gl_compatibility -- --benchmark --benchmark-seconds=60
```

Benchmark JSON is written under the game's user-data directory, named by renderer. Benchmark writes use a test checkpoint root. Desktop results do not establish Android performance, sustained thermals, native GPU memory, or controller feel. Use the same fixture and settings on the Thor before comparing.
