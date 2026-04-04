param(
    [Parameter(Mandatory)]
    [string]$OverlayName,

    [string]$RepoRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path),

    [string]$TargetRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path),

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$overlayRoot = Join-Path $RepoRoot "overlays\$OverlayName"
$overlayToolsRoot = Join-Path $overlayRoot 'tools'
$overlayManifestPath = Join-Path $overlayRoot 'tools-manifest.json'
$targetToolsRoot = Join-Path $TargetRoot 'tools'
$targetManifestPath = Join-Path $TargetRoot 'tools-manifest.json'

if (-not (Test-Path -LiteralPath $overlayRoot)) {
    throw "Overlay not found: $overlayRoot"
}
if (-not (Test-Path -LiteralPath $overlayToolsRoot)) {
    throw "Overlay tools directory not found: $overlayToolsRoot"
}
if (-not (Test-Path -LiteralPath $overlayManifestPath)) {
    throw "Overlay manifest not found: $overlayManifestPath"
}
if (-not (Test-Path -LiteralPath $targetToolsRoot)) {
    throw "Target tools directory not found: $targetToolsRoot"
}
if (-not (Test-Path -LiteralPath $targetManifestPath)) {
    throw "Target manifest not found: $targetManifestPath"
}

$overlayManifest = Get-Content -LiteralPath $overlayManifestPath -Raw | ConvertFrom-Json
$targetManifest = Get-Content -LiteralPath $targetManifestPath -Raw | ConvertFrom-Json

$copiedTools = @()
foreach ($toolName in @($overlayManifest.approved_tools)) {
    $sourcePath = Join-Path $overlayToolsRoot "$toolName.ps1"
    $destinationPath = Join-Path $targetToolsRoot "$toolName.ps1"

    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Overlay tool file not found: $sourcePath"
    }

    if ((Test-Path -LiteralPath $destinationPath) -and -not $Force) {
        throw "Target tool already exists: $destinationPath. Re-run with -Force to replace it."
    }

    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    $copiedTools += $toolName
}

$approved = [System.Collections.Generic.List[string]]::new()
foreach ($toolName in @($targetManifest.approved_tools)) {
    if (-not [string]::IsNullOrWhiteSpace($toolName) -and -not $approved.Contains($toolName)) {
        $approved.Add($toolName)
    }
}
foreach ($toolName in @($overlayManifest.approved_tools)) {
    if (-not $approved.Contains($toolName)) {
        $approved.Add($toolName)
    }
}

$disabled = [System.Collections.Generic.List[string]]::new()
foreach ($toolName in @($targetManifest.disabled_tools)) {
    if (
        -not [string]::IsNullOrWhiteSpace($toolName) -and
        -not ($toolName -in @($overlayManifest.approved_tools)) -and
        -not $disabled.Contains($toolName)
    ) {
        $disabled.Add($toolName)
    }
}

$updatedManifest = [ordered]@{
    approved_tools = @($approved)
    disabled_tools = @($disabled)
}

$updatedManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $targetManifestPath

Write-Host "Installed overlay '$OverlayName' into $TargetRoot" -ForegroundColor Cyan
Write-Host "Copied tools: $($copiedTools -join ', ')" -ForegroundColor Gray
Write-Host "Updated manifest: $targetManifestPath" -ForegroundColor Gray
