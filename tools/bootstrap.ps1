[CmdletBinding()]
param([switch]$SkipDownloads, [string]$InstallRoot = '', [string]$CacheRoot = '')

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LockPath = Join-Path $ProjectRoot 'dependencies.lock.json'
$Lock = Get-Content -Raw $LockPath | ConvertFrom-Json
$InstallRootResolved = if ([string]::IsNullOrWhiteSpace($InstallRoot)) { $ProjectRoot } else { [IO.Path]::GetFullPath($InstallRoot) }
$ToolsRoot = Join-Path $InstallRootResolved '.tools'
$Downloads = if ([string]::IsNullOrWhiteSpace($CacheRoot)) { Join-Path $ToolsRoot 'downloads' } else { [IO.Path]::GetFullPath($CacheRoot) }
$Reports = Join-Path $InstallRootResolved 'reports\logs'
New-Item -ItemType Directory -Force -Path $ToolsRoot,$Downloads,$Reports | Out-Null

function Get-Hash([string]$Path, [string]$Algorithm) {
    (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash.ToLowerInvariant()
}

function Ensure-Archive([string]$Name, [string]$Url, [string]$Algorithm, [string]$Expected) {
    $path = Join-Path $Downloads $Name
    if (-not (Test-Path -LiteralPath $path)) {
        if ($SkipDownloads) { throw "Required cached archive is missing: $path" }
        Invoke-WebRequest -Uri $Url -OutFile $path -UseBasicParsing
    }
    $actual = Get-Hash $path $Algorithm
    if ($actual -ne $Expected.ToLowerInvariant()) { throw "Hash mismatch for $Name (expected $Expected, got $actual)" }
    return $path
}

function Expand-ZipSafe([string]$Archive, [string]$Destination, [string[]]$AllowedNames = @(), [string]$StripPrefix = '') {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $root = [IO.Path]::GetFullPath($Destination).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $relative = $entry.FullName.Replace('/', [IO.Path]::DirectorySeparatorChar)
            if ($StripPrefix -ne '') {
                $prefix = $StripPrefix.Replace('/', [IO.Path]::DirectorySeparatorChar).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
                if (-not $relative.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
                $relative = $relative.Substring($prefix.Length)
            }
            if ($AllowedNames.Count -gt 0 -and $AllowedNames -notcontains $relative) { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $relative))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "Zip path traversal rejected: $($entry.FullName)" }
            if ($entry.FullName.EndsWith('/')) { New-Item -ItemType Directory -Force -Path $target | Out-Null; continue }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            if (-not (Test-Path -LiteralPath $target)) {
                $stream = $entry.Open(); $out = [IO.File]::Open($target, [IO.FileMode]::CreateNew)
                try { $stream.CopyTo($out) } finally { $out.Dispose(); $stream.Dispose() }
            }
        }
    } finally { $zip.Dispose() }
}

function Assert-InstalledFileMatches([string]$Archive, [string]$EntryName, [string]$DestinationRoot) {
    $target = Join-Path $DestinationRoot ($EntryName.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $target)) { return }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $entry = $zip.GetEntry($EntryName)
        if ($null -eq $entry) { throw "Archive entry missing: $EntryName" }
        $stream = $entry.Open(); $hash = [Security.Cryptography.SHA256]::Create()
        try { $archiveHash = ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLowerInvariant() } finally { $stream.Dispose(); $hash.Dispose() }
    } finally { $zip.Dispose() }
    if ((Get-Hash $target 'SHA256') -ne $archiveHash) { throw "Installed file differs from locked archive; refusing to overwrite: $target" }
}

$editorZip = Ensure-Archive 'Godot_v4.7.2-stable_win64.exe.zip' $Lock.engine.editor_url 'SHA512' $Lock.engine.editor_sha512
$templateArchive = Ensure-Archive 'Godot_v4.7.2-stable_export_templates.tpz' $Lock.engine.templates_url 'SHA512' $Lock.engine.templates_sha512
$voxelArchive = Ensure-Archive 'GodotVoxelExtension-v1.7x.zip' $Lock.voxel.url 'SHA256' $Lock.voxel.sha256
$mcpArchive = Ensure-Archive 'godot-ai-v3.2.5.zip' $Lock.mcp.plugin_url 'SHA256' $Lock.mcp.plugin_sha256

$toolsIgnore = Join-Path $ToolsRoot '.gdignore'
if (-not (Test-Path -LiteralPath $toolsIgnore)) { [IO.File]::WriteAllText($toolsIgnore, '') }

$editorDir = Join-Path $ToolsRoot 'godot-4.7.2'
Assert-InstalledFileMatches $editorZip 'Godot_v4.7.2-stable_win64.exe' $editorDir
Assert-InstalledFileMatches $editorZip 'Godot_v4.7.2-stable_win64_console.exe' $editorDir
Expand-ZipSafe $editorZip $editorDir
$templateDir = Join-Path $ToolsRoot 'templates'
foreach ($templateName in @('templates/android_debug.apk','templates/android_release.apk','templates/windows_debug_x86_64.exe','templates/windows_release_x86_64.exe','templates/version.txt')) { Assert-InstalledFileMatches $templateArchive $templateName $ToolsRoot }
Expand-ZipSafe $templateArchive $templateDir @('android_debug.apk','android_release.apk','windows_debug_x86_64.exe','windows_release_x86_64.exe','version.txt') 'templates/'
$voxelRoot = $InstallRootResolved
foreach ($voxelName in @('addons/zylann.voxel/voxel.gdextension','addons/zylann.voxel/bin/libvoxel.windows.editor.x86_64.dll','addons/zylann.voxel/bin/libvoxel.windows.template_release.x86_64.dll','addons/zylann.voxel/bin/libvoxel.android.editor.arm64.so','addons/zylann.voxel/bin/libvoxel.android.template_release.arm64.so')) { Assert-InstalledFileMatches $voxelArchive $voxelName $voxelRoot }
Expand-ZipSafe $voxelArchive $voxelRoot
$mcpRoot = Join-Path $InstallRootResolved 'dev\mcp'
Assert-InstalledFileMatches $mcpArchive 'addons/godot_ai/plugin.cfg' $mcpRoot
Expand-ZipSafe $mcpArchive $mcpRoot

"bootstrap ok editor=$($Lock.engine.version) voxel=$($Lock.voxel.tag) mcp=$($Lock.mcp.version)" | Tee-Object -FilePath (Join-Path $Reports 'bootstrap.log')
