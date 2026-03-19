# tests/Test-ApiRoundtrip.ps1
# Spike: make one raw Claude API call and dump everything.
# No parsing, no abstraction — just see what PS7 gives you back.
#
# Usage:
#   $env:ANTHROPIC_API_KEY = 'sk-ant-...'
#   pwsh -File .\tests\Test-ApiRoundtrip.ps1

$config = Get-Content (Join-Path $PSScriptRoot '..\config.json') -Raw | ConvertFrom-Json
$apiKey = [System.Environment]::GetEnvironmentVariable($config.api_key_env)
if (-not $apiKey) {
    Write-Error "Set `$env:$($config.api_key_env) first."
    exit 1
}

$body = @{
    model      = $config.model
    max_tokens = 1024
    messages   = @(@{ role = "user"; content = "Say hello in JSON format." })
} | ConvertTo-Json -Depth 5

Write-Host "`n── Request body ──" -ForegroundColor DarkGray
Write-Host $body

Write-Host "`n── Sending request... ──" -ForegroundColor DarkGray

try {
    $response = Invoke-RestMethod `
        -Uri "https://api.anthropic.com/v1/messages" `
        -Method Post `
        -Body $body `
        -ContentType "application/json; charset=utf-8" `
        -Headers @{
            "x-api-key"         = $apiKey
            "anthropic-version" = "2023-06-01"
        } `
        -TimeoutSec 60
}
catch {
    Write-Error "Request failed: $_"
    exit 1
}

Write-Host "`n── Full response (ConvertTo-Json -Depth 10) ──" -ForegroundColor Green
$response | ConvertTo-Json -Depth 10

Write-Host "`n── Content block types ──" -ForegroundColor Cyan
$response.content | ForEach-Object { "$($_.type) => $($_.GetType().FullName)" }

Write-Host "`n── First text block ──" -ForegroundColor Cyan
$response.content[0].text

Write-Host "`n── stop_reason ──" -ForegroundColor Cyan
$response.stop_reason

Write-Host "`n── Usage ──" -ForegroundColor Cyan
$response.usage | ConvertTo-Json
