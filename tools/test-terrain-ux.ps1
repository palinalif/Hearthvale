param(
    [ValidateSet('all','sculpt-core','preview-jobs','preview-live')]
    [string]$Suite = 'all'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

# Terrain shards need the same pinned editor/voxel import as sculpt, but the base
# sculpt regression workflow owns its five tests separately. Avoid running those
# tests again here just to obtain the editor.
& "$PSScriptRoot/test-sculpt-feedback.ps1" -Suite setup
if ($LASTEXITCODE -ne 0) { throw 'Terrain dependency setup failed' }

$root = Join-Path (Get-Location) '.tools/sculpt-ci'
$editor = Get-ChildItem $root -Filter '*_console.exe' | Select-Object -First 1 -ExpandProperty FullName
if (-not $editor) { throw 'Pinned Godot console editor missing' }

function Invoke-TerrainGate([string]$label) {
    $output = & $editor --headless --max-fps 60 --quit-after 7200 --path . --script "tests/$label.gd" 2>&1 | ForEach-Object { "$_" }
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Output $_ }
    $output | Set-Content -LiteralPath (Join-Path $root "$label.log")
    if ($exitCode -ne 0 -or ($output -match 'ERROR:|Parse Error:|FAIL:')) {
        throw "Gate failed: $label (exit=$exitCode)"
    }
    $joined = $output -join "`n"
    $plain = $joined -match 'failures=0'
    $json = $joined -match '"failures"\s*:\s*0' -and $joined -match '"ok"\s*:\s*true'
    if (-not ($plain -or $json)) { throw "Missing successful test receipt: $label" }
}

$groups = @{
    'sculpt-core' = @('sculpt_strength_test','sculpt_next_layer_test','sculpt_live_next_layer_test')
    'preview-jobs' = @('sculpt_occupancy_runs_test','sculpt_preview_job_test','sculpt_preview_performance_test')
    'preview-live' = @('sculpt_preview_live_test','m1_terrain_ux_test')
}
$selected = if ($Suite -eq 'all') { @('sculpt-core','preview-jobs','preview-live') } else { @($Suite) }
foreach ($group in $selected) {
    foreach ($test in $groups[$group]) { Invoke-TerrainGate $test }
}
Write-Output "TERRAIN_UX_SUITE_OK suite=$Suite"
