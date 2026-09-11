# Isolated CI workspace. Uses the same pinned Godot editor and voxel extension
# as the existing M1/sculpt gates; no signing keys, exports, or user saves.
param(
    [ValidateSet(
        'auto','setup','native','native-structure','native-assets','native-placement','native-ui',
        'mobile-core','mobile-window','mobile-house-ux','roof','joined-roof','facade',
        'catalogue','catalogue-capture','catalogue-behavior','all'
    )]
    [string]$Suite = 'auto'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

# Keep the historical no-argument cottage call lightweight while preserving
# `./tools/test-m1-placement.ps1` as the full local/manual suite.
if ($Suite -eq 'auto') {
    $Suite = if ($env:GITHUB_JOB -like 'cottage-*') { 'setup' } else { 'all' }
}

$lock = Get-Content dependencies.lock.json -Raw | ConvertFrom-Json
$root = Join-Path (Get-Location) '.tools/m1-placement-ci'
New-Item -ItemType Directory -Force $root | Out-Null
Set-Content -LiteralPath (Join-Path (Split-Path $root) '.gdignore') -Value ''

function Get-LockedArchive($url, $destination, $algorithm, $expected) {
    Invoke-WebRequest -Uri $url -OutFile $destination
    if ((Get-FileHash -LiteralPath $destination -Algorithm $algorithm).Hash.ToLowerInvariant() -ne $expected.ToLowerInvariant()) {
        throw "Archive hash mismatch: $destination"
    }
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
    if ($exitCode -ne 0 -or ($output -match 'ERROR:|Parse Error:|FAIL:')) {
        throw "Gate failed: $label (exit=$exitCode)"
    }
    if ($label -ne 'import') {
        $joined = $output -join "`n"
        $plain = $joined -match 'failures=0'
        $json = $joined -match '"failures"\s*:\s*0' -and $joined -match '"ok"\s*:\s*true'
        if (-not ($plain -or $json)) { throw "Missing successful test receipt: $label" }
    }
}

function Invoke-MobileReview(
    [string]$label,
    [string]$script,
    [int]$timeoutMs,
    [string[]]$requiredPatterns,
    [string[]]$extraArgs = @()
) {
    $review = Join-Path (Get-Location) '.tools/cottage-repair'
    New-Item -ItemType Directory -Force $review | Out-Null
    $safe = $label -replace '[^A-Za-z0-9_-]', '-'
    $out = Join-Path $review "$safe.out.log"
    $err = Join-Path $review "$safe.err.log"
    $arguments = @('--path', '.', '--rendering-method', 'mobile', '--rendering-driver', 'd3d12', '--audio-driver', 'Dummy', '--max-fps', '30', '--script', $script) + $extraArgs
    $process = Start-Process -FilePath $editor -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    if (-not $process.WaitForExit($timeoutMs)) {
        $process.Kill()
        $process.WaitForExit()
        throw "$label timed out"
    }
    $log = (Get-Content $out -Raw) + (Get-Content $err -Raw)
    Write-Output $log
    if ($process.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|Parse Error|ERROR:|FAIL:') {
        throw "$label failed"
    }
    foreach ($pattern in $requiredPatterns) {
        if ($log -notmatch $pattern) { throw "$label missing required receipt: $pattern" }
    }
}

# Every shard imports independently so it can run on a clean hosted runner.
Invoke-Gate 'import' @('--headless', '--path', '.', '--editor', '--import', '--quit')

$nativeStructure = @(
    'facade_depth_layout_test','joined_roof_course_test','roof_course_layout_test','m2_ground_wall_test',
    'm2_section_edit_test','m2_house_edit_ux_test','building_world_test','m2_roof_design_test',
    'm2_roof_accessories_test','m2_terrain_house_outline_test','m2_house_massing_test','m2_house_massing_edit_test',
    'm2_multi_floor_house_test','m2_upper_storey_detail_test','m2_upper_storey_auto_windows_test','m2_riverside_quoin_resize_test'
)
$nativeAssets = @(
    'magicavoxel_asset_test','foliage_asset_test','meadow_expansion_asset_test','woodland_asset_test',
    'size_variation_asset_test','vegetation_integration_test','m1_landscape_test'
)
$nativePlacement = @(
    'wall_attachment_placement_test','m1_attachment_placement_test','m1_building_placement_test','m2_placement_rotation_test',
    'm2_path_state_test','m2_path_placement_test','m2_path_cancel_feedback_test','m2_bridge_state_test',
    'm2_bridge_placement_test','m2_hamlet_detail_state_test','m2_garden_placement_test','m2_fence_placement_test',
    'm2_furniture_placement_test','m2_duplicate_detail_test','m2_attachment_preview_test','m2_attachment_boundary_test'
)
$nativeUi = @(
    'm2_build_browser_test','m2_home_catalogue_test','m2_home_options_layout_test','m2_pc_input_test',
    'm2_surface_material_picker_test','m2_decor_colour_test','m2_compact_colour_test','m2_window_style_expansion_test',
    'm2_window_customization_test','m2_window_alignment_test','m2_window_alignment_minimum_test','m2_path_render_test',
    'm1_controller_test','m1_building_camera_test','m1_window_layout_test','m1_cottage_edit_ux_test',
    'm1_ui_overhaul_test','m1_tool_ui_test','m1_full_ui_test'
)

function Invoke-NativeGroup([string[]]$tests) {
    foreach ($test in $tests) {
        Invoke-Gate $test @('--headless', '--path', '.', '--script', "tests/$test.gd")
    }
}

if ($Suite -in @('native-structure', 'native', 'all')) { Invoke-NativeGroup $nativeStructure }
if ($Suite -in @('native-assets', 'native', 'all')) {
    Invoke-NativeGroup $nativeAssets
    $meshingOutput = & python tests/magicavoxel_converter_test.py 2>&1 | ForEach-Object { "$_" }
    $meshingOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'MagicaVoxel converter regression failed' }
}
if ($Suite -in @('native-placement', 'native', 'all')) { Invoke-NativeGroup $nativePlacement }
if ($Suite -in @('native-ui', 'native', 'all')) { Invoke-NativeGroup $nativeUi }

if ($Suite -in @('mobile-window', 'mobile-core', 'all')) {
    Invoke-MobileReview 'window-alignment' 'tests/m2_window_alignment_test.gd' 180000 @(
        'WINDOW_ALIGNMENT_RESULT', '"ok"\s*:\s*true', '"captures"\s*:\s*6'
    ) @('--', '--require-rendering')
}
if ($Suite -in @('mobile-house-ux', 'mobile-core', 'all')) {
    Invoke-MobileReview 'house-ux' 'tests/m2_house_edit_ux_test.gd' 240000 @(
        '"ok"\s*:\s*true', '"captures"\s*:\s*4'
    ) @('--', '--require-rendering')
}

if ($Suite -in @('roof', 'all')) {
    & ./tools/test-roof-courses.ps1 -Editor $editor
}

if ($Suite -in @('joined-roof', 'all')) {
    & ./tools/test-joined-roof-courses.ps1 -Editor $editor
}

if ($Suite -in @('facade', 'all')) {
    & ./tools/test-facade-depth.ps1 -Editor $editor
}

if ($Suite -in @('catalogue', 'all')) {
    & ./tools/test-m2-build-browser.ps1 -Editor $editor -Phase all
}
if ($Suite -eq 'catalogue-capture') {
    & ./tools/test-m2-build-browser.ps1 -Editor $editor -Phase capture
}
if ($Suite -eq 'catalogue-behavior') {
    & ./tools/test-m2-build-browser.ps1 -Editor $editor -Phase behavior
}

Write-Output "PLACEMENT_SUITE_OK suite=$Suite"
