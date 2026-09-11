# Hosted-runner performance regression guard.
# This is deliberately normalized against same-run idle frame timing. It catches
# relative regressions on GitHub's Windows Mobile-renderer runner but never claims
# to emulate the Ayn Thor's Android/Adreno absolute FPS.
param(
    [int]$TimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$root = Join-Path (Get-Location) '.tools/m1-placement-ci'
$editor = Get-ChildItem $root -Filter '*_console.exe' -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $editor) {
    & ./tools/test-m1-placement.ps1 -Suite setup
    if ($LASTEXITCODE -ne 0) { throw 'Pinned Godot/voxel setup failed' }
    $editor = Get-ChildItem $root -Filter '*_console.exe' |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $editor) { throw 'Pinned Godot console editor missing after setup' }

$review = Join-Path (Get-Location) '.tools/performance'
New-Item -ItemType Directory -Force $review | Out-Null
$out = Join-Path $review 'm2-mobile-performance.out.log'
$err = Join-Path $review 'm2-mobile-performance.err.log'

$arguments = @(
    '--path', '.',
    '--rendering-method', 'mobile',
    '--rendering-driver', 'd3d12',
    '--audio-driver', 'Dummy',
    '--script', 'tests/m2_mobile_performance_guard.gd',
    '--',
    '--require-rendering'
)

$process = Start-Process -FilePath $editor -ArgumentList $arguments -WindowStyle Hidden `
    -RedirectStandardOutput $out -RedirectStandardError $err -PassThru

if (-not $process.WaitForExit($TimeoutMs)) {
    $process.Kill()
    $process.WaitForExit()
    throw 'M2 Mobile performance guard timed out'
}

$log = ''
if (Test-Path $out) { $log += Get-Content $out -Raw }
if (Test-Path $err) { $log += Get-Content $err -Raw }
Write-Output $log

if ($process.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|Parse Error|FAIL:') {
    throw "M2 Mobile performance guard failed (exit=$($process.ExitCode))"
}
if ($log -notmatch 'M2_PERFORMANCE_RESULT' -or $log -notmatch '"ok"\s*:\s*true') {
    throw 'M2 Mobile performance guard missing successful receipt'
}

Write-Output 'M2_PERFORMANCE_GUARD_OK'
