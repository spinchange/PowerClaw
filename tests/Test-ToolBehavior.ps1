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

$root = Split-Path $PSScriptRoot -Parent

Write-Host "`n-- Get-TopProcesses: Memory sort maps to WorkingSet64 --" -ForegroundColor Cyan
. (Join-Path $root "tools\Get-TopProcesses.ps1")
$actualMemory = @(Get-TopProcesses -SortBy Memory -Count 5)
$expectedMemory = @(Get-Process |
    Sort-Object WorkingSet64 -Descending |
    Select-Object -First 5)

Assert-True "Returned 5 processes for memory sort" ($actualMemory.Count -eq 5)
Assert-True "Top process IDs match direct WorkingSet64 sort" (
    (@($actualMemory.Id) -join ',') -eq (@($expectedMemory.Id) -join ',')
)

Write-Host "`n-- Search-Files: single quotes are escaped in SQL literals --" -ForegroundColor Cyan
$searchFile = Join-Path $root "tools\Search-Files.ps1"
$searchText = Get-Content -LiteralPath $searchFile -Raw

Assert-True "Helper escapes single quotes by doubling them" (
    ($searchText -match 'ConvertTo-SearchSqlLiteral') -and
    ($searchText -match '-replace')
)
Assert-True "FileName clause uses escaped literal helper" (
    $searchText -match '\$fileNamePattern = ConvertTo-SearchSqlLiteral'
)
Assert-True "ContentQuery clause uses escaped literal helper" (
    $searchText -match '\$contentLiteral = ConvertTo-SearchSqlLiteral'
)

Write-Host "`n-- tools-manifest: default workbench surface --" -ForegroundColor Cyan
$manifest = Get-Content (Join-Path $root "tools-manifest.json") -Raw | ConvertFrom-Json

Assert-True "Get-SystemSummary is listed once" (
    (@($manifest.approved_tools | Where-Object { $_ -eq 'Get-SystemSummary' })).Count -eq 1
)
Assert-True "Fetch-WebPage approved by default" (
    'Fetch-WebPage' -in $manifest.approved_tools -and
    'Fetch-WebPage' -notin $manifest.disabled_tools
)
Assert-True "Personal tools moved to overlay" (
    -not (Test-Path (Join-Path $root "tools\Search-MyJoNotes.ps1")) -and
    -not (Test-Path (Join-Path $root "tools\Search-MnVault.ps1")) -and
    (Test-Path (Join-Path $root "overlays\personal\tools\Search-MyJoNotes.ps1")) -and
    (Test-Path (Join-Path $root "overlays\personal\tools\Search-MnVault.ps1"))
)

Write-Host "`n-- Register-ClawTools: disabled entries are actually skipped --" -ForegroundColor Cyan
. (Join-Path $root 'registry\Register-ClawTools.ps1')
$tempRoot = Join-Path $env:TEMP "powerclaw-registry-test"
$tempTools = Join-Path $tempRoot 'tools'
$tempManifest = Join-Path $tempRoot 'tools-manifest.json'

New-Item -ItemType Directory -Path $tempTools -Force | Out-Null
Set-Content -LiteralPath (Join-Path $tempTools 'Get-Alpha.ps1') -Value @'
function Get-Alpha {
    [CmdletBinding()]
    param()
    'alpha'
}
'@
Set-Content -LiteralPath (Join-Path $tempTools 'Get-Beta.ps1') -Value @'
function Get-Beta {
    [CmdletBinding()]
    param()
    'beta'
}
'@
Set-Content -LiteralPath $tempManifest -Value @'
{
  "approved_tools": ["Get-Alpha", "Get-Beta", "Get-Beta"],
  "disabled_tools": ["Get-Beta"]
}
'@

$registered = @(Register-ClawTools -ToolsPath $tempTools -ManifestPath $tempManifest)
Assert-True "Approved tool registers once" (
    (@($registered | Where-Object Name -eq 'Get-Alpha')).Count -eq 1
)
Assert-True "Disabled tool is excluded even if approved" (
    (@($registered | Where-Object Name -eq 'Get-Beta')).Count -eq 0
)
Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n-- Tool schema: extra arguments are rejected at schema level --" -ForegroundColor Cyan
. (Join-Path $root 'registry\ConvertTo-ToolSchema.ps1')
$schema = ConvertTo-ClaudeToolSchema ([PSCustomObject]@{
    Name = 'Get-Test'
    Description = 'test tool'
    Parameters = @(
        [PSCustomObject]@{ Name = 'Path'; Type = 'String'; Required = $true }
    )
})

Assert-True "Schema sets additionalProperties=false" (
    $schema.input_schema.additionalProperties -eq $false
)

Write-Host "`n-- Results: $pass passed, $fail failed --" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
