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
foreach ($test in @('wall_attachment_placement_test','building_world_test','magicavoxel_asset_test','foliage_asset_test','meadow_expansion_asset_test','woodland_asset_test','size_variation_asset_test','vegetation_integration_test','m1_landscape_test','m1_attachment_placement_test','m1_building_placement_test','m2_placement_rotation_test','m2_home_catalogue_test','m2_home_options_layout_test','m2_pc_input_test','m2_path_state_test','m2_path_placement_test','m2_path_cancel_feedback_test','m2_bridge_state_test','m2_bridge_placement_test','m2_hamlet_detail_state_test','m2_garden_placement_test','m2_fence_placement_test','m2_furniture_placement_test','m2_duplicate_detail_test','m2_surface_material_picker_test','m2_decor_colour_test','m2_compact_colour_test','m2_attachment_preview_test','m2_attachment_boundary_test','m2_window_style_expansion_test','m2_window_customization_test','m2_window_alignment_test','m2_roof_design_test','m2_roof_accessories_test','m2_terrain_house_outline_test','m2_house_massing_test','m2_house_massing_edit_test','m2_multi_floor_house_test','m2_upper_storey_detail_test','m2_upper_storey_auto_windows_test','m2_riverside_quoin_resize_test','m2_path_render_test','m1_controller_test','m1_building_camera_test','m1_window_layout_test','m1_cottage_edit_ux_test','m1_ui_overhaul_test','m1_tool_ui_test','m1_full_ui_test')) {
    Invoke-Gate $test @('--headless', '--path', '.', '--script', "tests/$test.gd")
}
# The same regression also inspects and captures the actual Mobile result.
# Retained in the existing cottage diagnostics artifact; this gate precedes export.
$review = Join-Path (Get-Location) '.tools/cottage-repair'
New-Item -ItemType Directory -Force $review | Out-Null
$out = Join-Path $review 'window-alignment.out.log'
$err = Join-Path $review 'window-alignment.err.log'
$args = @('--path', '.', '--rendering-method', 'mobile', '--rendering-driver', 'd3d12', '--audio-driver', 'Dummy', '--max-fps', '30', '--script', 'tests/m2_window_alignment_test.gd', '--', '--require-rendering')
$process = Start-Process -FilePath $editor -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
if (-not $process.WaitForExit(180000)) { $process.Kill(); $process.WaitForExit(); throw 'Window alignment Mobile review timed out' }
$log = (Get-Content $out -Raw) + (Get-Content $err -Raw)
Write-Output $log
if ($process.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|Parse Error|ERROR:|FAIL:' -or $log -notmatch 'WINDOW_ALIGNMENT_RESULT' -or $log -notmatch '"ok"\s*:\s*true' -or $log -notmatch '"captures"\s*:\s*6') { throw 'Window alignment must pass actual Mobile checks and six captures before export' }
$meshingOutput = & python tests/magicavoxel_converter_test.py 2>&1 | ForEach-Object { "$_" }
$meshingOutput | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw 'MagicaVoxel converter regression failed' }
