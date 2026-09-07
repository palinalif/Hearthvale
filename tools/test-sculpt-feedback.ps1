# Isolated CI workspaces only. Uses existing dependency pins; no exports, MCP,
# signing keys, user saves, or changes to the project's dependency lock.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$lock = Get-Content dependencies.lock.json -Raw | ConvertFrom-Json
$root = Join-Path (Get-Location) '.tools/sculpt-ci'
New-Item -ItemType Directory -Force $root | Out-Null
Set-Content -LiteralPath (Join-Path (Split-Path $root) '.gdignore') -Value ''
function Get-LockedArchive($url, $destination, $algorithm, $expected) {
    Invoke-WebRequest -Uri $url -OutFile $destination
    if ((Get-FileHash -LiteralPath $destination -Algorithm $algorithm).Hash.ToLowerInvariant() -ne $expected.ToLowerInvariant()) {
        throw "Archive hash mismatch: $destination"
    }
}
Get-LockedArchive $lock.engine.editor_url (Join-Path $root 'editor.zip') 'SHA512' $lock.engine.editor_sha512
Get-LockedArchive $lock.voxel.url (Join-Path $root 'voxel.zip') 'SHA256' $lock.voxel.sha256
Expand-Archive -LiteralPath (Join-Path $root 'editor.zip') -DestinationPath $root -Force
Expand-Archive -LiteralPath (Join-Path $root 'voxel.zip') -DestinationPath (Get-Location) -Force
$editor = Get-ChildItem $root -Filter '*_console.exe' | Select-Object -First 1 -ExpandProperty FullName
if (-not $editor) { throw 'Pinned Godot console editor missing' }
$version = (& $editor --version | Out-String).Trim()
if ($version -ne $lock.engine.version) { throw "Unexpected engine: $version" }
function Invoke-Gate([string]$label, [string[]]$arguments) {
    $output = & $editor @arguments 2>&1 | ForEach-Object { "$_" }
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Output $_ }
    $output | Set-Content -LiteralPath (Join-Path $root "$label.log")
    if ($exitCode -ne 0 -or ($output -match 'ERROR:|Parse Error:|FAIL:')) {
        throw "Gate failed: $label (exit=$exitCode)"
    }
    if ($label -ne 'import') {
        $joined = $output -join "`n"
        $hasPlainReceipt = $joined -match 'failures=0'
        $hasJsonReceipt = $joined -match '"failures"\s*:\s*0' -and $joined -match '"ok"\s*:\s*true'
        if (-not ($hasPlainReceipt -or $hasJsonReceipt)) {
            throw "Missing successful test receipt: $label"
        }
    }
}
Invoke-Gate 'import' @('--headless', '--path', '.', '--editor', '--import', '--quit')
foreach ($test in @('smooth_neighbourhood_test','sculpt_smoothing_test','sculpt_test','m1_scaled_backend_test')) {
    Invoke-Gate $test @('--headless', '--path', '.', '--script', "tests/$test.gd")
}
