[CmdletBinding()]
param([switch]$Windows, [switch]$Compatibility, [switch]$CompatibilityOnly)

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

function Export-AndroidCompatibility {
    $overridePath = Join-Path $ProjectRoot 'override.cfg'
    if (Test-Path -LiteralPath $overridePath) { throw "Refusing to overwrite existing project override.cfg: $overridePath" }
    $projectPath = Join-Path $ProjectRoot 'project.godot'
    $backupPath = Join-Path $ProjectRoot '.tools\project.godot.compatibility.backup'
    if (Test-Path -LiteralPath $backupPath) { throw "Refusing to overwrite existing compatibility backup: $backupPath" }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $originalBytes = [IO.File]::ReadAllBytes($projectPath)
    $originalText = [IO.File]::ReadAllText($projectPath, $utf8)
    $basePattern = '(?m)^(renderer/rendering_method\s*=\s*)"[^"]*"(\s*)$'
    $mobilePattern = '(?m)^(renderer/rendering_method\.mobile\s*=\s*)"[^"]*"(\s*)$'
    $baseMatches = [Text.RegularExpressions.Regex]::Matches($originalText, $basePattern)
    $mobileMatches = [Text.RegularExpressions.Regex]::Matches($originalText, $mobilePattern)
    if ($baseMatches.Count -ne 1 -or $mobileMatches.Count -ne 1) { throw "Expected exactly one base and one mobile renderer setting in project.godot" }
    $temporaryText = [Text.RegularExpressions.Regex]::Replace($originalText, $basePattern, { param($m) $m.Groups[1].Value + '"gl_compatibility"' + $m.Groups[2].Value })
    $temporaryText = [Text.RegularExpressions.Regex]::Replace($temporaryText, $mobilePattern, { param($m) $m.Groups[1].Value + '"gl_compatibility"' + $m.Groups[2].Value })
    $temporaryBytes = $utf8.GetBytes($temporaryText)
    [IO.File]::WriteAllBytes($backupPath, $originalBytes)
    $mutated = $false
    try {
        [IO.File]::WriteAllBytes($projectPath, $temporaryBytes)
        $mutated = $true
        Export-Target 'debug' 'Android ARM64 Compatibility' 'builds/hearthvale-m1-compatibility.apk'
    } finally {
        if ($mutated) {
            $currentBytes = [IO.File]::ReadAllBytes($projectPath)
            $same = $currentBytes.Length -eq $temporaryBytes.Length
            if ($same) { for ($i = 0; $i -lt $currentBytes.Length; $i++) { if ($currentBytes[$i] -ne $temporaryBytes[$i]) { $same = $false; break } } }
            if (-not $same) { throw "project.godot changed during Compatibility export; original retained at $backupPath" }
            [IO.File]::WriteAllBytes($projectPath, $originalBytes)
            Remove-Item -LiteralPath $backupPath -Force
        }
    }
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
    if (-not $CompatibilityOnly) {
        Export-Target 'debug' 'Android ARM64' 'builds/hearthvale-m1-debug.apk'
        Export-Target 'release' 'Android ARM64' 'builds/hearthvale-m1-release.apk'
    }
    if ($Compatibility -or $CompatibilityOnly) { Export-AndroidCompatibility }
} finally {
    foreach ($name in $releaseVars) { [Environment]::SetEnvironmentVariable($name, $savedRelease[$name], 'Process') }
}
if ($Windows) {
    if (-not $CompatibilityOnly) {
        Export-Target 'debug' 'Windows' 'builds/hearthvale-m1-debug.exe'
        Export-Target 'release' 'Windows' 'builds/hearthvale-m1-release.exe'
    }
    if ($Compatibility -or $CompatibilityOnly) { Export-Target 'release' 'Windows Compatibility' 'builds/hearthvale-m1-compatibility.exe' }
}
"build ok mobile=$(-not $CompatibilityOnly) compatibility=$($Compatibility -or $CompatibilityOnly) windows=$Windows" | Tee-Object -FilePath (Join-Path $Logs 'build-summary.log')
