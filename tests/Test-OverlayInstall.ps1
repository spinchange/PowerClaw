$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$pass = 0
$fail = 0

function Assert-True {
    param(
        [string]$Label,
        [bool]$Condition
    )

    if ($Condition) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [FAIL] $Label" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "`n-- Overlay install helper: personal overlay copies tools and updates manifest --" -ForegroundColor Cyan

$tempRoot = Join-Path $env:TEMP 'powerclaw-overlay-test'
$targetRoot = Join-Path $tempRoot 'target'
$targetTools = Join-Path $targetRoot 'tools'
$targetManifest = Join-Path $targetRoot 'tools-manifest.json'

Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $targetTools -Force | Out-Null
Set-Content -LiteralPath $targetManifest -Value @'
{
  "approved_tools": ["Get-TopProcesses"],
  "disabled_tools": ["Search-MyJoNotes"]
}
'@

pwsh -NoProfile -File (Join-Path $root 'Install-PowerClawOverlay.ps1') `
    -OverlayName personal `
    -RepoRoot $root `
    -TargetRoot $targetRoot | Out-Null

$manifest = Get-Content -LiteralPath $targetManifest -Raw | ConvertFrom-Json

Assert-True "Search-MyJoNotes copied to target tools" (
    Test-Path -LiteralPath (Join-Path $targetTools 'Search-MyJoNotes.ps1')
)
Assert-True "Search-MnVault copied to target tools" (
    Test-Path -LiteralPath (Join-Path $targetTools 'Search-MnVault.ps1')
)
Assert-True "Overlay tools added to approved_tools" (
    ('Search-MyJoNotes' -in @($manifest.approved_tools)) -and
    ('Search-MnVault' -in @($manifest.approved_tools))
)
Assert-True "Overlay tools removed from disabled_tools" (
    ('Search-MyJoNotes' -notin @($manifest.disabled_tools)) -and
    ('Search-MnVault' -notin @($manifest.disabled_tools))
)

Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n-- Results: $pass passed, $fail failed --" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
