# core/Invoke-PowerClaw.ps1

function Invoke-PowerClaw {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Prompt,

        [switch]$DryRun,

        [switch]$Plan,

        [switch]$UseStub
    )

    Write-Host "PowerClaw v0.3" -ForegroundColor Cyan
    Write-Host "Prompt: $Prompt" -ForegroundColor Gray
    Write-Host ""

    $config = Get-Content (Join-Path $PSScriptRoot '..\config.json') -Raw | ConvertFrom-Json

    $tools = Register-ClawTools
    if ($tools.Count -eq 0) {
        Write-Error "No approved tools found. Check tools-manifest.json."
        return
    }

    $result = Invoke-ClawLoop `
        -UserGoal $Prompt `
        -Tools $tools `
        -MaxSteps $config.max_steps `
        -DryRun:$DryRun `
        -Plan:$Plan `
        -UseStub:$UseStub

    if ($result -and -not $Plan) {
        Write-Host "`n$result"
    }
}
