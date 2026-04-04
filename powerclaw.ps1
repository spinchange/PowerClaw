$ErrorActionPreference = 'Stop'

$repoManifest = Join-Path $PSScriptRoot 'PowerClaw.psd1'
if (Test-Path -LiteralPath $repoManifest) {
    Import-Module $repoManifest -Force
} else {
    Import-Module PowerClaw -Force
}

& Invoke-PowerClaw @args
