param([Parameter(Mandatory=$true)][string]$Editor)
$ErrorActionPreference = 'Stop'
$review = Join-Path (Get-Location) '.tools/cottage-repair/build-browser'
New-Item -ItemType Directory -Force $review | Out-Null
$out = Join-Path $review 'mobile.out.log'
$err = Join-Path $review 'mobile.err.log'
$arguments = @('--path','.','--rendering-method','mobile','--rendering-driver','d3d12','--audio-driver','Dummy','--max-fps','30','--script','tests/m2_build_browser_test.gd','--','--require-rendering')
$process = Start-Process -FilePath $Editor -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
if (-not $process.WaitForExit(240000)) { $process.Kill(); $process.WaitForExit(); throw 'Build browser review timed out' }
$log = (Get-Content $out -Raw) + (Get-Content $err -Raw)
Write-Output $log
if ($process.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|Parse Error|ERROR:|FAIL:' -or $log -notmatch 'BUILD_BROWSER_RESULT' -or $log -notmatch '"ok"\s*:\s*true' -or $log -notmatch '"captures"\s*:\s*5') { throw 'Build catalogue requires actual Mobile thumbnails and all five captures' }
