# Reuse the locked native installation, import and sculpt regression gates.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/test-sculpt-feedback.ps1"
foreach ($test in @('sculpt_strength_test', 'sculpt_next_layer_test', 'sculpt_preview_job_test', 'sculpt_preview_performance_test', 'm1_terrain_ux_test')) {
    Invoke-Gate $test @('--headless', '--max-fps', '60', '--path', '.', '--script', "tests/$test.gd")
}
