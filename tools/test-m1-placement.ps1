# Isolated CI workspace. Uses the same pinned Godot editor and voxel extension
# as the existing M1/sculpt gates; no signing keys, exports, or user saves.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$lock = Get-Content dependencies.lock.json -Raw | ConvertFrom-Json
$root = Join-Path (Get-Location) '.tools/m1-placement-ci'
New-Item -ItemType Directory -Force $root | Out-Null
Set-Content -LiteralPath (Join-Path (Split-Path $root) '.gdignore') -Value ''
function Get-LockedArchive($url, $destination, $algorithm, $expected) {
    Invoke-WebRequest -Uri $url -OutFile $destination
    if ((Get-FileHash -LiteralPath $destination -Algorithm $algorithm).Hash.ToLowerInvariant() -ne $expected.ToLowerInvariant()) { throw "Archive hash mismatch: $destination" }
}
Get-LockedArchive $lock.engine.editor_url (Join-Path $root 'editor.zip') 'SHA512' $lock.engine.editor_sha512
Get-LockedArchive $lock.voxel.url (Join-Path $root 'voxel.zip') 'SHA256' $lock.voxel.sha256
Expand-Archive -LiteralPath (Join-Path $root 'editor.zip') -DestinationPath $root -Force
Expand-Archive -LiteralPath (Join-Path $root 'voxel.zip') -DestinationPath (Get-Location) -Force
$editor = Get-ChildItem $root -Filter '*_console.exe' | Select-Object -First 1 -ExpandProperty FullName
if (-not $editor) { throw 'Pinned Godot console editor missing' }
if ((& $editor --version | Out-String).Trim() -ne $lock.engine.version) { throw 'Unexpected Godot version' }
function Invoke-Gate([string]$label, [string[]]$arguments) {
    $output = & $editor @arguments 2>&1 | ForEach-Object { "$_" }
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Output $_ }
    if ($exitCode -ne 0 -or ($output -match 'ERROR:|Parse Error:|FAIL:')) { throw "Gate failed: $label (exit=$exitCode)" }
    if ($label -ne 'import') {
        $joined = $output -join "`n"
        $plain = $joined -match 'failures=0'
        $json = $joined -match '"failures"\s*:\s*0' -and $joined -match '"ok"\s*:\s*true'
        if (-not ($plain -or $json)) { throw "Missing successful test receipt: $label" }
    }
}
Invoke-Gate 'import' @('--headless', '--path', '.', '--editor', '--import', '--quit')
foreach ($test in @('wall_attachment_placement_test','building_world_test','m1_attachment_placement_test','m1_building_placement_test','m1_controller_test','m1_building_camera_test')) {
    Invoke-Gate $test @('--headless', '--path', '.', '--script', "tests/$test.gd")
}
