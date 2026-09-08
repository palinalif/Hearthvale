[CmdletBinding()]
param([int]$TimeoutMs = 120000)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot
$Godot = Join-Path $ProjectRoot '.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
$Logs = Join-Path $ProjectRoot 'reports\logs'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
if (-not (Test-Path -LiteralPath $Godot)) { throw "Pinned Godot editor is missing: $Godot" }

function Invoke-GodotBounded([string]$Name, [string[]]$Arguments) {
    $log = Join-Path $Logs ("check-{0}.log" -f $Name)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Godot
    $psi.WorkingDirectory = $ProjectRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Arguments = (($Arguments | ForEach-Object { '"' + $_.Replace('"','\\"') + '"' }) -join ' ')
    $process = New-Object Diagnostics.Process; $process.StartInfo = $psi
    if (-not $process.Start()) { throw "Could not start Godot for $Name" }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMs)) {
        $process.Kill(); $process.WaitForExit()
        $text = $stdout.Result + [Environment]::NewLine + $stderr.Result + [Environment]::NewLine + 'TIMEOUT'
        [IO.File]::WriteAllText($log, $text)
        throw "Timed out: $Name; see $log"
    }
    $text = $stdout.Result + [Environment]::NewLine + $stderr.Result
    [IO.File]::WriteAllText($log, $text)
    Write-Output $text
    if ($process.ExitCode -ne 0 -or $text -match '(?i)SCRIPT ERROR|ERROR:') { throw "Check failed: $Name; see $log" }
    if ($text -match '(?m)^FAIL:') { throw "Check reported FAIL lines: $Name; see $log" }
    $requiresFinalJson = ($Name -eq 'm1-controller' -or $Name -like 'm1-acceptance*' -or $Name -like 'terrain-resolution*' -or $Name -like 'm1-landscape*' -or $Name -eq 'visual-grid' -or $Name -eq 'cottage-detail-visual')
    if ($requiresFinalJson -and -not [regex]::IsMatch($text, '(?m)^\s*\{.*"ok"\s*:\s*true.*\}\s*$')) {
        throw "Check did not emit a passing final JSON sentinel: $Name; see $log"
    }
}

Invoke-GodotBounded 'import' @('--headless','--path','.','--editor','--import','--quit','--max-fps','60')
Invoke-GodotBounded 'native-probe' @('--headless','--path','.','--scene','res://probes/dependency_probe.tscn','--max-fps','60','--','--probe')
Invoke-GodotBounded 'checkpoint' @('--headless','--path','.','--script','res://tests/checkpoint_test.gd','--max-fps','60')
Invoke-GodotBounded 'checkpoint-write-fixture' @('--headless','--path','.','--script','res://tests/checkpoint_test.gd','--max-fps','60','--','--write-fixture')
Invoke-GodotBounded 'checkpoint-read-fixture' @('--headless','--path','.','--script','res://tests/checkpoint_test.gd','--max-fps','60','--','--read-fixture')
Invoke-GodotBounded 'checkpoint-write-second' @('--headless','--path','.','--script','res://tests/checkpoint_test.gd','--max-fps','60','--','--write-second')
Invoke-GodotBounded 'checkpoint-read-second' @('--headless','--path','.','--script','res://tests/checkpoint_test.gd','--max-fps','60','--','--read-second')
Invoke-GodotBounded 'm1-checkpoint' @('--headless','--path','.','--script','res://tests/m1_checkpoint_test.gd','--max-fps','60')
Invoke-GodotBounded 'm1-checkpoint-write-fixture' @('--headless','--path','.','--script','res://tests/m1_checkpoint_test.gd','--max-fps','60','--','--write-fixture')
Invoke-GodotBounded 'm1-checkpoint-read-fixture' @('--headless','--path','.','--script','res://tests/m1_checkpoint_test.gd','--max-fps','60','--','--read-fixture')
Invoke-GodotBounded 'm1-checkpoint-write-second' @('--headless','--path','.','--script','res://tests/m1_checkpoint_test.gd','--max-fps','60','--','--write-second')
Invoke-GodotBounded 'm1-checkpoint-read-second' @('--headless','--path','.','--script','res://tests/m1_checkpoint_test.gd','--max-fps','60','--','--read-second')
Invoke-GodotBounded 'backend' @('--headless','--path','.','--script','res://tests/backend_test.gd','--max-fps','60')
Invoke-GodotBounded 'sculpt' @('--headless','--path','.','--script','res://tests/sculpt_test.gd','--max-fps','60')
Invoke-GodotBounded 'm1-scaled-backend' @('--headless','--path','.','--script','res://tests/m1_scaled_backend_test.gd','--max-fps','60')
Invoke-GodotBounded 'm1-riverbank-visual' @('--headless','--path','.','--script','res://tests/m1_riverbank_visual_test.gd','--max-fps','60')
Invoke-GodotBounded 'm1-visual' @('--headless','--path','.','--script','res://tests/m1_visual_test.gd','--max-fps','60')
Invoke-GodotBounded 'building-world' @('--headless','--path','.','--script','res://tests/building_world_test.gd','--max-fps','60')
Invoke-GodotBounded 'cottage-detail-visual' @('--headless','--path','.','--script','res://tests/cottage_detail_visual_test.gd','--max-fps','60')
Invoke-GodotBounded 'visual-grid' @('--headless','--path','.','--script','res://tests/visual_grid_test.gd','--max-fps','60')
Invoke-GodotBounded 'magicavoxel-asset' @('--headless','--path','.','--script','res://tests/magicavoxel_asset_test.gd','--max-fps','60')
Invoke-GodotBounded 'plant-target' @('--headless','--path','.','--script','res://tests/plant_target_test.gd','--max-fps','60')
$fixtureTag = [DateTime]::UtcNow.Ticks.ToString()
Invoke-GodotBounded 'terrain-resolution' @('--headless','--path','.','--script','res://tests/terrain_resolution_test.gd','--max-fps','60','--',("--fixture-root=user://resolution-check-"+$fixtureTag))
Invoke-GodotBounded 'terrain-resolution-cold' @('--headless','--path','.','--script','res://tests/terrain_resolution_test.gd','--max-fps','60','--','--read-fixture',("--fixture-root=user://resolution-check-"+$fixtureTag))
Invoke-GodotBounded 'm1-landscape' @('--headless','--path','.','--script','res://tests/m1_landscape_test.gd','--max-fps','60','--',("--fixture-root=user://landscape-check-"+$fixtureTag))
Invoke-GodotBounded 'm1-landscape-cold' @('--headless','--path','.','--script','res://tests/m1_landscape_test.gd','--max-fps','60','--','--read-fixture',("--fixture-root=user://landscape-check-"+$fixtureTag))
Invoke-GodotBounded 'controller' @('--headless','--path','.','--script','res://tests/controller_test.gd','--max-fps','60')
Invoke-GodotBounded 'm1-controller' @('--headless','--path','.','--script','res://tests/m1_controller_test.gd','--max-fps','60')
# The write-fixture mode runs the full acceptance scenario before saving its
# expectation. Run it once, then verify a separate cold process.
Invoke-GodotBounded 'm1-acceptance-write-fixture' @('--headless','--path','.','--script','res://tests/m1_acceptance_test.gd','--max-fps','60','--','--write-fixture')
Invoke-GodotBounded 'm1-acceptance-read-fixture' @('--headless','--path','.','--script','res://tests/m1_acceptance_test.gd','--max-fps','60','--','--read-fixture')
Write-Output "check ok; logs=$Logs"
