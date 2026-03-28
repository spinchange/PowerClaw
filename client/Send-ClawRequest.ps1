# client/Send-ClawRequest.ps1
#
# Provider-neutral dispatcher. Reads config.provider and routes to the
# appropriate provider function. Stub mode bypasses all providers.
#
# All providers must return:
#   [PSCustomObject]@{
#       Type      = "tool_call" | "final_answer"
#       ToolName  = <string>      # tool_call only
#       ToolInput = <hashtable>   # tool_call only
#       ToolUseId = <string>      # tool_call only
#       Content   = <string>      # final_answer only
#   }

function Send-ClawRequest {
    [CmdletBinding()]
    param(
        [string]$SystemPrompt,
        [array]$Messages,
        [array]$ToolSchemas,
        [switch]$UseStub
    )

    if ($UseStub) {
        # Stub mode: always call first tool with defaults
        # Alternates: returns tool_call on first call, final_answer on second
        $isFollowUp = $Messages.Count -gt 2
        if ($isFollowUp) {
            return [PSCustomObject]@{
                Type    = "final_answer"
                Content = "[Stub] Here are the results from the tool execution above."
            }
        }
        return [PSCustomObject]@{
            Type      = "tool_call"
            ToolName  = "Get-TopProcesses"
            ToolInput = @{ SortBy = "CPU"; Count = 5 }
            ToolUseId = "stub_$(Get-Random)"
        }
    }

    $config = Get-Content (Join-Path $PSScriptRoot '..\config.json') -Raw | ConvertFrom-Json

    switch ($config.provider) {
        "claude" { return Send-ClaudeRequest -SystemPrompt $SystemPrompt -Messages $Messages -ToolSchemas $ToolSchemas -Config $config }
        "openai" { return Send-OpenAiRequest -SystemPrompt $SystemPrompt -Messages $Messages -ToolSchemas $ToolSchemas -Config $config }
        default  { throw "Unknown provider '$($config.provider)'. Check config.json." }
    }
}
