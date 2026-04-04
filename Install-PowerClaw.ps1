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
    "Install-PowerClawOverlay.ps1",
    "client",
    "core",
    "overlays",
    "registry",
    "tools",
    "config.example.json",
    "config.claude.example.json",
    "config.openai.example.json",
    "tools-manifest.json"
)

if (Test-Path -LiteralPath (Join-Path $repoRoot 'config.json')) {
    $copyItems += 'config.json'
}

foreach ($item in $copyItems) {
    $source = Join-Path $repoRoot $item
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required install item missing: $source"
    }

    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
}

$installedConfigPath = Join-Path $destination 'config.json'
if (-not (Test-Path -LiteralPath $installedConfigPath)) {
    Copy-Item `
        -LiteralPath (Join-Path $destination 'config.example.json') `
        -Destination $installedConfigPath `
        -Force
}

$launcherDestination = $null
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
    Write-Host "Installed launcher to $launcherDestination"
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Ensure '$ModuleRoot' is on PSModulePath." -ForegroundColor Gray
if (-not $SkipLauncher) {
    Write-Host "  2. Ensure '$BinRoot' is on PATH." -ForegroundColor Gray
    Write-Host "  3. Edit '$installedConfigPath' or replace it with config.openai.example.json / config.claude.example.json." -ForegroundColor Gray
    Write-Host "  4. Open a new PowerShell session and run: powerclaw -UseStub ""hello""" -ForegroundColor Gray
} else {
    Write-Host "  2. Edit '$installedConfigPath' or replace it with config.openai.example.json / config.claude.example.json." -ForegroundColor Gray
    Write-Host "  3. Import the module and run: powerclaw -UseStub ""hello""" -ForegroundColor Gray
}
Write-Host "  5. Run Test-PowerClawSetup after setting your API key." -ForegroundColor Gray
