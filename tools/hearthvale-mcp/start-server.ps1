$ErrorActionPreference = 'Stop'
$serverRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent (Split-Path -Parent $serverRoot)
$env:HEARTHVALE_REPO_ROOT = $repoRoot
Set-Location $serverRoot
& node (Join-Path $serverRoot 'src\server.mjs')
exit $LASTEXITCODE
