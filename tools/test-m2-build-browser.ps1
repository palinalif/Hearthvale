param([Parameter(Mandatory=$true)][string]$Editor)
$ErrorActionPreference = 'Stop'
$review = Join-Path (Get-Location) '.tools/cottage-repair/build-browser'
New-Item -ItemType Directory -Force $review | Out-Null
$out = Join-Path $review 'mobile.out.log'
$err = Join-Path $review 'mobile.err.log'
$arguments = @('--path','.','--rendering-method','mobile','--rendering-driver','d3d12','--audio-driver','Dummy','--max-fps','30','--script','tests/m2_build_browser_test.gd','--','--require-rendering')
# m2_build_browser_test.gd intentionally allows 65s for scene restore plus up to
# 30s for each of five category render waits (215s) before its own assertions
# can report a rendering/cache failure. The outer watchdog must leave room for
# process startup, controller/frame settling, five screenshot readbacks, and
# teardown on the Microsoft Basic Render Driver used by hosted Windows runners.
$timeoutMs = 300000
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
