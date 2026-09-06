[CmdletBinding()]
param([ValidateSet('cottage','close','dig','near','far','occluded')][string]$View='cottage', [switch]$Clean, [switch]$Edited, [switch]$Front, [string]$Name='m1-review')
$ErrorActionPreference='Stop'
if ($Name -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Use a simple capture name.' }
$taskRoot=Split-Path -Parent $PSScriptRoot
Set-Location $taskRoot
$taskFrames='.tools/capture-'+$Name
New-Item -ItemType Directory -Force $taskFrames | Out-Null
$taskArguments=@('--path','.','--disable-vsync','--write-movie',($taskFrames+'/frame.png'),'--fixed-fps','30','--quit-after','60','--',('--review-'+$View))
if ($Clean) { $taskArguments+='--review-clean' }
if ($Edited) { $taskArguments+='--review-edited' }
if ($Front) { $taskArguments+='--review-front' }
$taskExe=Join-Path $taskRoot '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe'
$taskOut=Join-Path $taskRoot ('reports/logs/'+$Name+'.out.log')
$taskErr=Join-Path $taskRoot ('reports/logs/'+$Name+'.err.log')
$taskProcess=Start-Process -FilePath $taskExe -WorkingDirectory $taskRoot -ArgumentList $taskArguments -WindowStyle Hidden -RedirectStandardOutput $taskOut -RedirectStandardError $taskErr -PassThru
if (-not $taskProcess.WaitForExit(55000)) { $taskProcess.Kill(); throw 'Capture timed out.' }
$taskLog=(Get-Content $taskOut -Raw)+(Get-Content $taskErr -Raw)
if ($taskProcess.ExitCode -ne 0 -or $taskLog -match 'SCRIPT ERROR|ERROR:') { throw 'Capture failed; inspect its logs.' }
$taskResult='reports/screenshots/'+$Name+'.png'
Copy-Item ($taskFrames+'/frame00000059.png') $taskResult
Write-Output $taskResult
