param(
    [Parameter(Mandatory=$true)][string]$Editor,
    [ValidateSet('all','capture','behavior')][string]$Phase = 'all'
)
$ErrorActionPreference = 'Stop'
$review = Join-Path (Get-Location) '.tools/cottage-repair/build-browser'
New-Item -ItemType Directory -Force $review | Out-Null
$out = Join-Path $review "$Phase.out.log"
$err = Join-Path $review "$Phase.err.log"
$extra = @('--require-rendering')
if ($Phase -eq 'capture') { $extra += '--capture-phase' }
elseif ($Phase -eq 'behavior') { $extra += '--behavior-phase' }
$arguments = @('--path','.','--rendering-method','mobile','--rendering-driver','d3d12','--audio-driver','Dummy','--max-fps','30','--script','tests/m2_build_browser_test.gd','--') + $extra
# The full local phase keeps the historical slow-host watchdog. CI fans capture
# and behavior into separate runners, preserving every assertion while removing
# the serial post-capture tail from the critical path.
$timeoutMs = if ($Phase -eq 'behavior') { 240000 } else { 420000 }
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
    throw "Build browser $Phase review timed out after $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s"
}
$stopwatch.Stop()
$log = (Get-Content $out -Raw) + (Get-Content $err -Raw)
Write-Output $log
Write-Output "BUILD_BROWSER_ELAPSED_SECONDS=$([math]::Round($stopwatch.Elapsed.TotalSeconds, 1)) phase=$Phase"
if ($process.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|Parse Error|ERROR:|FAIL:' -or $log -notmatch 'BUILD_BROWSER_RESULT' -or $log -notmatch '"ok"\s*:\s*true') {
    throw "Build catalogue $Phase phase failed"
}
if ($Phase -in @('all','capture') -and $log -notmatch '"captures"\s*:\s*5') {
    throw 'Build catalogue capture phase requires all five actual Mobile captures'
}
if ($Phase -eq 'behavior' -and $log -notmatch '"phase"\s*:\s*"behavior"') {
    throw 'Build catalogue behavior phase receipt missing'
}
