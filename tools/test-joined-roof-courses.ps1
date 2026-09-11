param([Parameter(Mandatory=$true)][string]$Editor)
$ErrorActionPreference = 'Stop'
$review = Join-Path (Get-Location) '.tools/cottage-repair/joined-roof-courses'
New-Item -ItemType Directory -Force $review | Out-Null
$out = Join-Path $review 'mobile.out.log'
$err = Join-Path $review 'mobile.err.log'
$arguments = @('--path','.','--rendering-method','mobile','--rendering-driver','d3d12','--audio-driver','Dummy','--max-fps','30','--script','tests/joined_roof_course_render_test.gd')
$process = Start-Process -FilePath $Editor -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
if (-not $process.WaitForExit(300000)) { $process.Kill(); $process.WaitForExit(); throw 'Joined roof course Mobile review timed out' }
$log = (Get-Content $out -Raw) + (Get-Content $err -Raw)
Write-Output $log
if ($process.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|Parse Error|ERROR:|FAIL:' -or $log -notmatch 'JOINED_COURSE_RENDER' -or $log -notmatch '"ok"\s*:\s*true' -or $log -notmatch '"captures"\s*:\s*8') { throw 'Joined roof courses require actual Mobile verification and eight comparison frames' }
