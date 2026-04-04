# client/providers/Send-ClaudeRequest.ps1
#
# Claude (Anthropic) provider. Called by Send-ClawRequest dispatcher.
# Returns the canonical provider response object:
#   [PSCustomObject]@{
#       Type      = "tool_call" | "final_answer"
#       ToolName  = <string>      # tool_call only
#       ToolInput = <hashtable>   # tool_call only
#       ToolUseId = <string>      # tool_call only
#       Content   = <string>      # final_answer only
#   }

function Resolve-ClaudeApiErrorMessage {
    [CmdletBinding()]
    param(
        [int]$Status,
        [string]$Detail,
        [string]$ApiKeyEnv
    )

    $parsedDetail = $null
    $parsedMessage = $null
    $parsedType = $null

    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        try {
            $parsedDetail = $Detail | ConvertFrom-Json -Depth 10
            if ($parsedDetail.error) {
                $parsedMessage = [string]$parsedDetail.error.message
                $parsedType = [string]$parsedDetail.error.type
            }
        }
        catch {
        }
    }

    $bestDetail = if (-not [string]::IsNullOrWhiteSpace($parsedMessage)) { $parsedMessage } else { $Detail }

    switch ($Status) {
        401 {
            return "Invalid API key. Check `$env:$ApiKeyEnv."
        }
        429 {
            if (-not [string]::IsNullOrWhiteSpace($bestDetail)) {
                return "Rate limited by Claude. Wait a moment and try again. Detail: $bestDetail"
            }

            return 'Rate limited by Claude. Wait a moment and try again.'
        }
        529 {
            if (-not [string]::IsNullOrWhiteSpace($bestDetail)) {
                return "Claude API is overloaded. Try again shortly. Detail: $bestDetail"
            }

            return 'Claude API is overloaded. Try again shortly.'
        }
        default {
            if (-not [string]::IsNullOrWhiteSpace($bestDetail)) {
                return "API call failed (HTTP $Status): $bestDetail"
            }

            if (-not [string]::IsNullOrWhiteSpace($parsedType)) {
                return "API call failed (HTTP $Status): $parsedType"
            }

            return "API call failed (HTTP $Status)."
        }
    }
}

function Send-ClaudeRequest {
    [CmdletBinding()]
    param(
        [string]$SystemPrompt,
        [array]$Messages,
        [array]$ToolSchemas,
        [object]$Config
    )

    $apiKey = [System.Environment]::GetEnvironmentVariable($Config.api_key_env)

    if (-not $apiKey) {
        throw "API key not found in env var '$($Config.api_key_env)'. Set it with: `$env:$($Config.api_key_env) = 'sk-ant-...' and confirm config.json uses provider='claude'."
    }

    $body = @{
        model      = $Config.model
        max_tokens = $Config.max_tokens
        system     = $SystemPrompt
        messages   = $Messages
        tools      = $ToolSchemas
    }

    # CRITICAL: default depth 2 silently truncates nested tool schemas — always use -Depth 10
    $jsonBody = $body | ConvertTo-Json -Depth 10

    Write-Verbose "Request body ($($jsonBody.Length) chars):"
    Write-Verbose $jsonBody

    try {
        $response = Invoke-RestMethod `
            -Uri "https://api.anthropic.com/v1/messages" `
            -Method Post `
            -Body $jsonBody `
            -ContentType "application/json; charset=utf-8" `
            -Headers @{
                "x-api-key"         = $apiKey
                "anthropic-version" = "2023-06-01"
            } `
            -TimeoutSec 60
    }
    catch {
        if ($_.Exception.Response) {
            $status = $_.Exception.Response.StatusCode.value__
            $detail = $_.ErrorDetails.Message
            throw (Resolve-ClaudeApiErrorMessage -Status $status -Detail $detail -ApiKeyEnv $Config.api_key_env)
        } else {
            throw "API call failed (no HTTP response): $($_.Exception.Message)"
        }
    }

    # Claude returns content as an array of blocks.
    # tool_use blocks: type, id, name, input
    # text blocks:     type, text
    $toolBlock = $response.content | Where-Object { $_.type -eq "tool_use" } | Select-Object -First 1

    if ($response.stop_reason -eq "tool_use" -and $toolBlock) {
        # CRITICAL: $toolBlock.input arrives as PSCustomObject, not hashtable.
        # Splatting requires a hashtable — convert explicitly.
        $inputHash = @{}
        if ($toolBlock.input -is [System.Management.Automation.PSCustomObject]) {
            foreach ($prop in $toolBlock.input.PSObject.Properties) {
                $inputHash[$prop.Name] = $prop.Value
            }
        }
        elseif ($toolBlock.input -is [hashtable]) {
            $inputHash = $toolBlock.input
        }

        return [PSCustomObject]@{
            Type      = "tool_call"
            ToolName  = $toolBlock.name
            ToolInput = $inputHash
            ToolUseId = $toolBlock.id
        }
    }
    else {
        $textBlock = $response.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1
        return [PSCustomObject]@{
            Type    = "final_answer"
            Content = if ($textBlock) { $textBlock.text } else { "(empty response)" }
        }
    }
}
