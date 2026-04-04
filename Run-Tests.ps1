param(
    [string]$Path = (Join-Path $PSScriptRoot 'tests\PowerClaw.Tests.ps1')
)

$requiredVersion = [version]'5.7.1'
$available = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1

if (-not $available -or $available.Version -lt $requiredVersion) {
    throw "Pester $requiredVersion or newer is required. Install with: Install-Module -Name Pester -RequiredVersion $requiredVersion -Scope CurrentUser -Force -SkipPublisherCheck"
}

Import-Module Pester -MinimumVersion $requiredVersion -Force

$config = [PesterConfiguration]::Default
$config.Run.Path = $Path
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$config.TestRegistry.Enabled = $false

$result = Invoke-Pester -Configuration $config
if ($result.FailedCount -gt 0) {
    exit 1
}
