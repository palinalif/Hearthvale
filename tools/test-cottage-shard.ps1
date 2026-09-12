param(
    [Parameter(Mandatory=$true)]
    [ValidateSet(
        'native-interaction','native-resize','native-visual',
        'upper-openings','ui-style','detail-grid','fine-prop','foliage-halfsize',
        'cottage-detail','home-variants','decoration-variants','paths','hamlet'
    )]
    [string]$Shard
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

# Each shard runs on a clean hosted runner. Keep dependency/bootstrap behavior
# identical to the former monolithic cottage job, but make it explicit so the
# matrix job name does not affect test-m1-placement.ps1's historical auto mode.
./tools/test-m1-placement.ps1 -Suite setup
if ($LASTEXITCODE -ne 0) { throw 'Pinned Godot/voxel setup failed' }

$editor = Get-ChildItem '.tools/m1-placement-ci' -Filter '*_console.exe' | Select-Object -First 1 -ExpandProperty FullName
if (-not $editor) { throw 'Pinned editor missing' }

$review = Join-Path (Get-Location) '.tools/cottage-repair'
New-Item -ItemType Directory -Force $review | Out-Null

function Invoke-NativeTests([string[]]$tests) {
    foreach ($test in $tests) {
        $output = & $editor --headless --max-fps 60 --quit-after 7200 --path . --script "tests/$test.gd" 2>&1 | ForEach-Object { "$_" }
        $exitCode = $LASTEXITCODE
        $output | Tee-Object -FilePath (Join-Path $review "$test.log")
        $joined = $output -join "`n"
        $plain = $joined -match 'failures=0'
        $json = $joined -match '"failures"\s*:\s*0' -and $joined -match '"ok"\s*:\s*true'
        if ($exitCode -ne 0 -or ($output -match 'ERROR:|Parse Error:|FAIL:') -or -not ($plain -or $json)) {
            throw "Cottage regression failed: $test"
        }
    }
}

function Invoke-MobileReview(
    [string]$label,
    [string]$script,
    [int]$timeoutMs,
    [string[]]$requiredPatterns,
    [string[]]$extraArgs = @()
) {
    $safe = $label -replace '[^A-Za-z0-9_-]', '-'
    $out = Join-Path $review "$safe.out.log"
    $err = Join-Path $review "$safe.err.log"
    $args = @('--path', '.', '--rendering-method', 'mobile', '--rendering-driver', 'd3d12', '--audio-driver', 'Dummy', '--max-fps', '30', '--script', $script) + $extraArgs
    $process = Start-Process -FilePath $editor -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
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

switch ($Shard) {
    'native-interaction' {
        Invoke-NativeTests @(
            'm1_cottage_targeting_playtest_test',
            'm1_playtest_repair_test',
            'm1_terrain_settings_input_test',
            'm1_recovery_dpad_test',
            'm1_terrain_navigation_test'
        )
    }
    'native-resize' {
        Invoke-NativeTests @(
            'cottage_handle_resize_test',
            'm1_resize_handles_test',
            'm1_house_actions_test'
        )
    }
    'native-visual' {
        Invoke-NativeTests @(
            'cottage_render_stability_test',
            'cottage_detail_visual_test'
        )
    }
    'upper-openings' {
        Invoke-MobileReview 'upper-openings' 'tests/m2_upper_storey_detail_test.gd' 180000 @(
            'UPPER_STOREY_GEOMETRY checked=[1-9][0-9]* unverified=0',
            'm2_upper_storey_detail_test checks=[1-9][0-9]* failures=0'
        ) @('--', '--require-rendering')
    }
    'ui-style' {
        Invoke-MobileReview 'ui-style' 'tests/m2_placement_rotation_render_test.gd' 300000 @(
            'COTTAGE_RENDER_START',
            'failures=0'
        )
    }
    'detail-grid' {
        Invoke-MobileReview 'detail-grid' 'tests/visual_grid_test.gd' 180000 @(
            '"ok"\s*:\s*true',
            '"unverified_headless_instances"\s*:\s*0'
        ) @('--', '--require-rendering')
    }
    'fine-prop' {
        Invoke-MobileReview 'fine-prop' 'tests/fine_prop_render_test.gd' 120000 @('"ok"\s*:\s*true')
    }
    'foliage-halfsize' {
        Invoke-MobileReview 'foliage-halfsize' 'tests/foliage_halfsize_render_test.gd' 120000 @('"ok"\s*:\s*true')
    }
    'cottage-detail' {
        Invoke-MobileReview 'cottage-detail' 'tests/cottage_detail_render_test.gd' 180000 @(
            'COTTAGE_DETAIL_RENDER_RESULT',
            '"failures"\s*:\s*0'
        )
    }
    'home-variants' {
        Invoke-MobileReview 'home-variants' 'tests/m2_home_variants_render_test.gd' 120000 @('"ok"\s*:\s*true')
    }
    'decoration-variants' {
        Invoke-MobileReview 'decoration-variants' 'tests/m2_decoration_variants_render_test.gd' 120000 @(
            'M2_DECORATION_RENDER_RESULT',
            '"ok"\s*:\s*true'
        )
    }
    'paths' {
        Invoke-NativeTests @(
            'm2_painted_path_region_test',
            'm2_painted_path_authority_test'
        )
        Invoke-MobileReview 'paths' 'tests/m2_path_render_test.gd' 180000 @(
            '"ok"\s*:\s*true',
            '"capture"'
        )
    }
    'hamlet' {
        Invoke-MobileReview 'hamlet' 'tests/m2_hamlet_composition_render_test.gd' 180000 @(
            'M2_HAMLET_RENDER_RESULT',
            '"ok"\s*:\s*true'
        )
    }
}

Write-Output "COTTAGE_SHARD_OK shard=$Shard"
