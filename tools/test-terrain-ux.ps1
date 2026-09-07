# Reuse the locked native installation, import and sculpt regression gates.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/test-sculpt-feedback.ps1"
Invoke-Gate 'sculpt_strength_test' @('--headless', '--path', '.', '--script', 'tests/sculpt_strength_test.gd')
# Further gates are added with their implementation, not marked passing here.
