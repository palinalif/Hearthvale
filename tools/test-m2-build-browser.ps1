param([Parameter(Mandatory=$true)][string]$Editor)
$ErrorActionPreference = 'Stop'
$review = Join-Path (Get-Location) '.tools/cottage-repair/build-browser'
New-Item -ItemType Directory -Force $review | Out-Null
$out = Join-Path $review 'mobile.out.log'
$err = Join-Path $review 'mobile.err.log'
$arguments = @('--path','.','--rendering-method','mobile','--rendering-driver','d3d12','--audio-driver','Dummy','--max-fps','30','--script','tests/m2_build_browser_test.gd','--','--require-rendering')
# This is an end-to-end actual-Mobile test: five rendered category captures are
# followed by controller placement/cancel/history/reload checks. On the same
# source and windows-2025 image, one Basic Render Driver host finished in ~172s,
# while a clean slower host needed ~220s just to reach the fifth capture; the
# prior green run then needed another 68s for the preserved post-capture checks.
# Keep the enclosing watchdog above that observed slow-host envelope. The test's
# own 65s scene-ready and 30s-per-category cache deadlines remain unchanged.
$timeoutMs = 420000
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$process = Start-Process -FilePath $Editor -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
if (-not $process.WaitForExit($timeoutMs)) {
    $process.Kill()
    $process.WaitForExit()
    $stopwatch.Stop()
    $partialLog = ''
    if (Test-Path $out) { $partialLog += Get-Content $out -Raw -ErrorAction SilentlyContinue }
    if (Test-Path $err) { $partialLog += Get-Content $err -Raw -ErrorAction SilentlyContinue }
    if (-not [string]::IsNullOrWhiteSpace($partialLog)) { Write-Output $partialLog }
    throw "Build browser review timed out after $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s"
}
$stopwatch.Stop()
$log = (Get-Content $out -Raw) + (Get-Content $err -Raw)
Write-Output $log
Write-Output "BUILD_BROWSER_ELAPSED_SECONDS=$([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))"
if ($process.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|Parse Error|ERROR:|FAIL:' -or $log -notmatch 'BUILD_BROWSER_RESULT' -or $log -notmatch '"ok"\s*:\s*true' -or $log -notmatch '"captures"\s*:\s*5') { throw 'Build catalogue requires actual Mobile thumbnails and all five captures' }
