[CmdletBinding()]
param([switch]$Windows, [switch]$Compatibility)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot
$Godot = Join-Path $ProjectRoot '.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
$Logs = Join-Path $ProjectRoot 'reports\logs'
$Builds = Join-Path $ProjectRoot 'builds'
New-Item -ItemType Directory -Force -Path $Logs,$Builds | Out-Null
if (-not (Test-Path -LiteralPath $Godot)) { throw "Pinned Godot editor is missing: $Godot. Run tools/bootstrap.ps1." }

function Export-Target([string]$Mode, [string]$Preset, [string]$Output) {
    $log = Join-Path $Logs ("build-{0}-{1}.log" -f $Preset.Replace(' ', '-').ToLowerInvariant(), $Mode)
    $args = @('--headless','--path','.');
    if ($Mode -eq 'debug') { $args += @('--export-debug',$Preset,$Output) } else { $args += @('--export-release',$Preset,$Output) }
    $oldAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $outputText = (& $Godot @args 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldAction
    $outputText | Tee-Object -FilePath $log
    if ($exitCode -ne 0 -or $outputText -match '(?i)SCRIPT ERROR|ERROR:') { throw "Godot $Mode export failed or reported errors for $Preset; see $log" }
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $Output))) { throw "Export did not create $Output; see $log" }
}

$releaseVars = @('GODOT_ANDROID_KEYSTORE_RELEASE_PATH','GODOT_ANDROID_KEYSTORE_RELEASE_USER','GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')
$savedRelease = @{}
foreach ($name in $releaseVars) { $savedRelease[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$debugKeystore = Join-Path ([Environment]::GetEnvironmentVariable('APPDATA')) 'Godot\keystores\debug.keystore'
if (-not (Test-Path -LiteralPath $debugKeystore)) { $debugKeystore = Join-Path ([Environment]::GetEnvironmentVariable('USERPROFILE')) '.android\debug.keystore' }
if ([string]::IsNullOrWhiteSpace($savedRelease['GODOT_ANDROID_KEYSTORE_RELEASE_PATH'])) {
    if (-not (Test-Path -LiteralPath $debugKeystore)) { throw "No release keystore configured. Set GODOT_ANDROID_KEYSTORE_RELEASE_* or provide local Android debug.keystore." }
    [Environment]::SetEnvironmentVariable('GODOT_ANDROID_KEYSTORE_RELEASE_PATH', $debugKeystore, 'Process')
    [Environment]::SetEnvironmentVariable('GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'androiddebugkey', 'Process')
    [Environment]::SetEnvironmentVariable('GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD', 'android', 'Process')
}
try {
    Export-Target 'debug' 'Android ARM64' 'builds/hearthvale-m0-debug.apk'
    Export-Target 'release' 'Android ARM64' 'builds/hearthvale-m0-release.apk'
    if ($Compatibility) { Export-Target 'debug' 'Android ARM64 Compatibility' 'builds/hearthvale-m0-compatibility.apk' }
} finally {
    foreach ($name in $releaseVars) { [Environment]::SetEnvironmentVariable($name, $savedRelease[$name], 'Process') }
}
if ($Windows) {
    Export-Target 'debug' 'Windows' 'builds/hearthvale-m0-debug.exe'
    Export-Target 'release' 'Windows' 'builds/hearthvale-m0-release.exe'
    if ($Compatibility) { Export-Target 'release' 'Windows Compatibility' 'builds/hearthvale-m0-compatibility.exe' }
}
"build ok android=debug,release compatibility=$Compatibility windows=$Windows" | Tee-Object -FilePath (Join-Path $Logs 'build-summary.log')
