param(
    [string]$ModuleRoot = "C:\dev\powershell-modules",
    [string]$BinRoot = "C:\dev\bin",
    [switch]$SkipLauncher,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestPath = Join-Path $repoRoot "PowerClaw.psd1"

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Module manifest not found at $manifestPath"
}

$manifest = Import-PowerShellDataFile -Path $manifestPath
$moduleName = Split-Path -LeafBase $manifestPath
$moduleVersion = [string]$manifest.ModuleVersion

if (-not $moduleVersion) {
    throw "ModuleVersion is missing from $manifestPath"
}

$destination = Join-Path $ModuleRoot $moduleName
$destination = Join-Path $destination $moduleVersion

if (Test-Path -LiteralPath $destination) {
    if (-not $Force) {
        throw "Destination already exists: $destination. Re-run with -Force to replace it."
    }

    Remove-Item -LiteralPath $destination -Recurse -Force
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null

$copyItems = @(
    "PowerClaw.psd1",
    "PowerClaw.psm1",
    "powerclaw.ps1",
    "client",
    "core",
    "registry",
    "tools",
    "config.json",
    "tools-manifest.json"
)

foreach ($item in $copyItems) {
    $source = Join-Path $repoRoot $item
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required install item missing: $source"
    }

    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
}

if (-not $SkipLauncher) {
    New-Item -ItemType Directory -Path $BinRoot -Force | Out-Null

    $launcherSource = Join-Path $repoRoot "powerclaw.ps1"
    $launcherDestination = Join-Path $BinRoot "powerclaw.ps1"

    if ((Test-Path -LiteralPath $launcherDestination) -and -not $Force) {
        throw "Launcher already exists: $launcherDestination. Re-run with -Force to replace it, or use -SkipLauncher."
    }

    Copy-Item -LiteralPath $launcherSource -Destination $launcherDestination -Force
}

Write-Host "Installed $moduleName $moduleVersion to $destination"
if (-not $SkipLauncher) {
    Write-Host "Installed launcher to $(Join-Path $BinRoot 'powerclaw.ps1')"
}
