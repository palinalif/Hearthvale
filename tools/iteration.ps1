#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Check','Targeted','Capture','Export','All')][string]$Stage = 'Check',
    [string[]]$Tests = @(),
    [string]$Name = ('m1-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [ValidateRange(1,3600000)][int]$TimeoutMs = 240000,
    [switch]$Plan
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Set-Location $taskRoot
if ($Name -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Name must contain only letters, digits, underscore or hyphen.' }
$normalizedTests = @($Tests | ForEach-Object { $_.Replace('\','/') })
if ($Stage -eq 'Targeted' -and $normalizedTests.Count -eq 0) { throw 'Targeted requires -Tests tests/name.gd.' }
if ($Stage -ne 'Targeted' -and $normalizedTests.Count) { throw '-Tests is only used with Targeted.' }
if (@($normalizedTests | Select-Object -Unique).Count -ne $normalizedTests.Count) { throw 'Duplicate test paths.' }
foreach ($test in $normalizedTests) {
    if ($test -notmatch '^tests/[a-zA-Z0-9_-]+\.gd$' -or -not (Test-Path -LiteralPath (Join-Path $taskRoot $test) -PathType Leaf)) {
        throw "Invalid or missing test: $test"
    }
}
$run = "reports/logs/iteration-$Name"
$outputDir = "builds/iteration-$Name"
$godot = Join-Path $taskRoot '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
$pwsh = Join-Path $PSHOME 'pwsh.exe'
$steps = [Collections.Generic.List[object]]::new()
function Add-Step([string]$Label, [string]$Executable, [string[]]$Arguments, [string]$Sentinel = '', [string[]]$Artifacts = @(), [int]$Deadline = $TimeoutMs) {
    $steps.Add([ordered]@{name=$Label; executable=$Executable; arguments=$Arguments; sentinel=$Sentinel; artifacts=$Artifacts; timeout_ms=$Deadline})
}
$passingJson = '(?m)^\s*\{[^\r\n]*"ok"\s*:\s*true[^\r\n]*\}\s*$'
if ($Stage -in 'Check','All') {
    # check.ps1 imports and runs the full acceptance write/cold-read exactly once.
    Add-Step 'check' $pwsh @('-NoProfile','-File','tools/check.ps1','-TimeoutMs',"$TimeoutMs") '(?m)^check ok;' @() ([Math]::Max($TimeoutMs,1800000))
} else {
    Add-Step 'import' $godot @('--headless','--path','.','--editor','--import','--quit','--max-fps','60')
}
if ($Stage -eq 'Targeted') {
    foreach ($test in $normalizedTests) {
        Add-Step ('test-' + [IO.Path]::GetFileNameWithoutExtension($test)) $godot @('--headless','--path','.','--script',('res://' + $test),'--max-fps','60') ($passingJson + '|(?m)^\w+ checks=\d+ failures=0\s*$')
    }
}
if ($Stage -in 'Capture','All') {
    Add-Step 'mobile-grid' $godot @('--path','.','--script','res://tests/visual_grid_test.gd','--max-fps','60','--','--require-rendering') $passingJson
    foreach ($view in 'cottage','close','edited') {
        $captureName = "$Name-$view"
        $captureArgs = @('-NoProfile','-File','tools/capture-m1.ps1','-View',$(if ($view -eq 'edited') {'close'} else {$view}),'-Name',$captureName,'-Clean')
        if ($view -in 'close','edited') { $captureArgs += '-Front' }
        if ($view -eq 'edited') { $captureArgs += '-Edited' }
        Add-Step "capture-$view" $pwsh $captureArgs '' @("reports/screenshots/$captureName.png")
    }
}
if ($Stage -in 'Export','All') {
    $apk = "$outputDir/android-debug.apk"
    $exe = "$outputDir/windows-debug.exe"
    Add-Step 'android-export' $godot @('--headless','--path','.','--export-debug','Android ARM64',$apk) '' @($apk)
    Add-Step 'windows-export' $godot @('--headless','--path','.','--export-debug','Windows',$exe) '' @($exe,"$outputDir/windows-debug.pck")
    Add-Step 'apk-verification' 'python' @('tools/verify-m1-apks.py','--apk',$apk,'--report',"$run/apk-verification.json") '"ok"\s*:\s*true' @("$run/apk-verification.json")
}
# Validate collisions even for Plan; it performs no process execution or writes.
$protected = @($run,$outputDir)
foreach ($step in $steps) { $protected += $step.artifacts }
if ($Stage -in 'Capture','All') {
    foreach ($view in 'cottage','close','edited') {
        $protected += @(".tools/capture-$Name-$view","reports/logs/$Name-$view.out.log","reports/logs/$Name-$view.err.log")
    }
}
foreach ($path in $protected) { if (Test-Path -LiteralPath $path) { throw "Name collision: $path; choose a fresh -Name." } }
if ($Plan) { [ordered]@{mode='plan';stage=$Stage;name=$Name;steps=$steps.ToArray()} | ConvertTo-Json -Depth 7; return }
# Resolve executables before creating an output directory or starting any stage.
foreach ($step in $steps) { $step.executable = (Get-Command $step.executable -ErrorAction Stop).Source }
New-Item -ItemType Directory -Path $run -Force | Out-Null
if ($Stage -in 'Export','All') { New-Item -ItemType Directory -Path $outputDir | Out-Null }
$receipt = [ordered]@{
    name=$Name; stage=$Stage; started_utc=[DateTime]::UtcNow.ToString('o'); status='running'
    physical_thor='not_run'; visual_approval='pending'; stages=@(); artifacts=@(); omitted_gates=@()
}
foreach ($gate in 'Check','Capture','Export') { if ($Stage -ne 'All' -and $Stage -ne $gate) { $receipt.omitted_gates += $gate } }
foreach ($step in $steps) {
    $receipt.stages += [ordered]@{name=$step.name;status='not_run';executable=$step.executable;arguments=$step.arguments;log="$run/$($step.name).log"}
}
function Invoke-Step($Step, $Entry) {
    $Entry.status = 'running'
    $process = [Diagnostics.Process]::new()
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Step.executable; $info.WorkingDirectory = $taskRoot
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    foreach ($argument in $Step.arguments) { $info.ArgumentList.Add([string]$argument) }
    $process.StartInfo = $info
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw "Could not start $($Step.name)" }
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($Step.timeout_ms)
        if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
        $text = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
        if ($timedOut) { $text += "`nTIMEOUT" }
        [IO.File]::WriteAllText((Join-Path $taskRoot $Entry.log),$text)
        $Entry.exit_code = $process.ExitCode
        if ($timedOut) { throw "Timed out: $($Step.name)" }
        if ($process.ExitCode -ne 0 -or $text -match '(?i)SCRIPT ERROR|ERROR:|(?m)^FAIL:') { throw "Failed: $($Step.name); see $($Entry.log)" }
        if ($Step.sentinel -and $text -notmatch $Step.sentinel) { throw "Missing passing sentinel: $($Step.name)" }
        foreach ($artifact in $Step.artifacts) {
            if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) { throw "Missing artifact: $artifact" }
            $receipt.artifacts += [ordered]@{path=$artifact;sha256=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()}
        }
        $Entry.status = 'passed'
        Write-Output "$($Step.name): passed"
    } catch {
        $Entry.status = 'failed'; $Entry.error = $_.Exception.Message
        if (-not (Test-Path -LiteralPath $Entry.log)) { [IO.File]::WriteAllText((Join-Path $taskRoot $Entry.log),$Entry.error) }
        throw
    } finally { $Entry.elapsed_ms=$timer.ElapsedMilliseconds; $process.Dispose() }
}
try {
    for ($index=0; $index -lt $steps.Count; $index++) { Invoke-Step $steps[$index] $receipt.stages[$index] }
    $receipt.status = 'passed'
} catch { $receipt.status='failed'; $receipt.error=$_.Exception.Message; throw }
finally {
    $receipt.finished_utc=[DateTime]::UtcNow.ToString('o')
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$run/receipt.json" -Encoding utf8
}
Write-Output "receipt: $run/receipt.json"
