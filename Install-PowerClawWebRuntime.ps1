param(
    [string]$RuntimeRoot = (Join-Path $env:USERPROFILE '.powerclaw-playwright\PwHost'),
    [string]$ProjectName = 'PwHost',
    [string]$Framework = 'net10.0',
    [switch]$SkipBrowserInstall
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet was not found on PATH. Install a .NET SDK before installing the PowerClaw web runtime."
}

if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    throw "pwsh was not found on PATH. PowerShell 7 is required to install the PowerClaw web runtime."
}

$projectRoot = Join-Path $RuntimeRoot $ProjectName
$playwrightScript = Join-Path $projectRoot "bin\Debug\$Framework\playwright.ps1"
$debugRoot = Join-Path $projectRoot 'bin\Debug'

New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null

Push-Location $RuntimeRoot
try {
    & dotnet new console -n $ProjectName --framework $Framework --force

    Push-Location $projectRoot
    try {
        & dotnet add package Microsoft.Playwright
        & dotnet build

        if (-not (Test-Path -LiteralPath $playwrightScript)) {
            throw "Playwright bootstrap script was not found at $playwrightScript after build."
        }

        if (-not $SkipBrowserInstall) {
            & pwsh -File $playwrightScript install chromium
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    Pop-Location
}

Write-Host "Installed PowerClaw web runtime to $projectRoot" -ForegroundColor Cyan
Write-Host "Build output root: $debugRoot" -ForegroundColor Gray
Write-Host "Set POWERCLAW_PLAYWRIGHT_BUILD to '$debugRoot' if you want to override the default lookup path." -ForegroundColor Gray
if ($SkipBrowserInstall) {
    Write-Host "Browser install was skipped. Run: pwsh -File `"$playwrightScript`" install chromium" -ForegroundColor Yellow
}
