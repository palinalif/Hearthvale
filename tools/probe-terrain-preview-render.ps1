# An unavailable renderer is explicitly NOT RUN, never a graphics pass.
# A started Mobile test with shader/assertion errors fails the job.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$folder = Join-Path (Get-Location) '.tools/terrain-ux'
New-Item -ItemType Directory -Force $folder | Out-Null
$editor = Get-ChildItem '.tools/sculpt-ci' -Filter '*_console.exe' | Select-Object -First 1 -ExpandProperty FullName
if (-not $editor) { throw 'Pinned editor missing; run native gates first' }
foreach ($driver in @('vulkan', 'd3d12')) {
    $out = Join-Path $folder "render-$driver.out.log"
    $err = Join-Path $folder "render-$driver.err.log"
    $arguments = @('--path', '.', '--rendering-method', 'mobile', '--rendering-driver', $driver, '--disable-vsync', '--script', 'tests/sculpt_preview_render_test.gd', '--', "--output=.tools/terrain-ux/preview-$driver")
    $process = Start-Process -FilePath $editor -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    if (-not $process.WaitForExit(60000)) {
        $process.Kill()
        $process.WaitForExit()
        Add-Content $err 'Render probe timed out'
    }
    $log = (Get-Content $out -Raw) + (Get-Content $err -Raw)
    if ($log -match 'SCRIPT ERROR|Parse Error|FAIL:' -or ($log -match 'PREVIEW_RENDER_START' -and ($log -match 'ERROR:' -or $log -notmatch 'failures=0'))) {
        throw "Started renderer/test failed: inspect $out and $err"
    }
    if ($process.ExitCode -eq 0 -and $log -match 'PREVIEW_RENDER_START' -and $log -match 'failures=0') {
        Set-Content (Join-Path $folder 'render-status.log') "PASS: synthetic Mobile bulk/setter pixel parity via $driver. Not integrated M1/Thor performance or art acceptance."
        Write-Output $log
        exit 0
    }
}
Set-Content (Join-Path $folder 'render-status.log') 'NOT RUN: neither Vulkan nor D3D12 initialized an actual Mobile renderer. Initialization logs retained. No graphics, GPU performance or visual approval claimed.'
Write-Output (Get-Content (Join-Path $folder 'render-status.log'))
