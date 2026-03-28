# PowerClaw.psm1 — Module root

$moduleRoot = $PSScriptRoot

# Core
. "$moduleRoot\core\Invoke-PowerClaw.ps1"
. "$moduleRoot\core\Invoke-ClawLoop.ps1"

# Client — providers must load before the dispatcher
. "$moduleRoot\client\providers\Send-ClaudeRequest.ps1"
. "$moduleRoot\client\providers\Send-OpenAiRequest.ps1"
. "$moduleRoot\client\Send-ClawRequest.ps1"

# Registry
. "$moduleRoot\registry\Register-ClawTools.ps1"
. "$moduleRoot\registry\ConvertTo-ToolSchema.ps1"

# Safety
# . "$moduleRoot\safety\Test-ClawSafety.ps1"   # Phase 3
# . "$moduleRoot\safety\Write-ClawLog.ps1"      # Phase 3

Export-ModuleMember -Function 'Invoke-PowerClaw'
