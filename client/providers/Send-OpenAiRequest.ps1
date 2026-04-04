# client/providers/Send-OpenAiRequest.ps1
#
# OpenAI provider. Called by Send-ClawRequest dispatcher.
# Returns the canonical provider response object:
#   [PSCustomObject]@{
#       Type      = "tool_call" | "final_answer"
#       ToolName  = <string>      # tool_call only
#       ToolInput = <hashtable>   # tool_call only
#       ToolUseId = <string>      # tool_call only
#       Content   = <string>      # final_answer only
#   }
#
# Message history translation (Claude format in → OpenAI format out):
#   { role:"assistant", content:[{ type:"tool_use", id, name, input }] }
#     → { role:"assistant", content:$null, tool_calls:[{ id, type:"function", function:{ name, arguments:"<json>" } }] }
#   { role:"user", content:[{ type:"tool_result", tool_use_id, content }] }
#     → { role:"tool", tool_call_id, content }
#   All other messages pass through unchanged.

function Send-OpenAiRequest {
    [CmdletBinding()]
    param(
        [string]$SystemPrompt,
        [array]$Messages,
        [array]$ToolSchemas,
        [object]$Config
    )

    $apiKey = [System.Environment]::GetEnvironmentVariable($Config.api_key_env)

    if (-not $apiKey) {
        throw "API key not found in env var '$($Config.api_key_env)'. Set it with: `$env:$($Config.api_key_env) = 'sk-...' and confirm config.json uses provider='openai'."
    }

    # Convert Claude tool schemas → OpenAI function-calling format
    $openAiTools = @($ToolSchemas | ForEach-Object {
        @{
            type     = "function"
            function = @{
                name        = $_.name
                description = $_.description
                parameters  = $_.input_schema
            }
        }
    })

    # Build OpenAI message list: system message first, then translated history
    $openAiMessages = [System.Collections.Generic.List[object]]::new()
    $openAiMessages.Add(@{ role = "system"; content = $SystemPrompt })

    foreach ($msg in $Messages) {
        # Claude assistant tool_use block → OpenAI assistant tool_calls
        if ($msg.role -eq "assistant" -and $msg.content -is [array]) {
            $toolUseBlock = $msg.content | Where-Object { $_.type -eq "tool_use" } | Select-Object -First 1
            if ($toolUseBlock) {
                $openAiMessages.Add(@{
                    role       = "assistant"
                    content    = $null
                    tool_calls = @(@{
                        id       = $toolUseBlock.id
                        type     = "function"
                        function = @{
                            name      = $toolUseBlock.name
                            # OpenAI expects arguments as a JSON string
                            arguments = ($toolUseBlock.input | ConvertTo-Json -Depth 5 -Compress)
                        }
                    })
                })
                continue
            }
        }

        # Claude user tool_result block → OpenAI tool role
        if ($msg.role -eq "user" -and $msg.content -is [array]) {
            $toolResultBlock = $msg.content | Where-Object { $_.type -eq "tool_result" } | Select-Object -First 1
            if ($toolResultBlock) {
                $openAiMessages.Add(@{
                    role         = "tool"
                    tool_call_id = $toolResultBlock.tool_use_id
                    content      = $toolResultBlock.content
                })
                continue
            }
        }

        # Plain user/assistant message — pass through
        $openAiMessages.Add(@{
            role    = $msg.role
            content = $msg.content
        })
    }

    $body = @{
        model                = $Config.model
        max_completion_tokens = $Config.max_tokens
        messages             = $openAiMessages.ToArray()
    }
    if ($openAiTools.Count -gt 0) {
        $body['tools'] = $openAiTools
    }

    # CRITICAL: default depth 2 silently truncates nested tool schemas — always use -Depth 10
    $jsonBody = $body | ConvertTo-Json -Depth 10

    Write-Verbose "Request body ($($jsonBody.Length) chars):"
    Write-Verbose $jsonBody

    try {
        $response = Invoke-RestMethod `
            -Uri "https://api.openai.com/v1/chat/completions" `
            -Method Post `
            -Body $jsonBody `
            -ContentType "application/json; charset=utf-8" `
            -Headers @{
                "Authorization" = "Bearer $apiKey"
            } `
            -TimeoutSec 60
    }
    catch {
        if ($_.Exception.Response) {
            $status = $_.Exception.Response.StatusCode.value__
            $detail = $_.ErrorDetails.Message
            switch ($status) {
                401     { throw "Invalid API key. Check `$env:$($Config.api_key_env)." }
                429     { throw "Rate limited. Wait a moment and try again." }
                default { throw "API call failed (HTTP $status): $detail" }
            }
        } else {
            throw "API call failed (no HTTP response): $($_.Exception.Message)"
        }
    }

    $choice = $response.choices | Select-Object -First 1

    if ($choice.finish_reason -eq "tool_calls" -and $choice.message.tool_calls) {
        $toolCall = $choice.message.tool_calls | Select-Object -First 1

        # OpenAI arguments arrive as a JSON string — parse and convert to hashtable
        $inputHash = @{}
        $parsedArgs = $toolCall.function.arguments | ConvertFrom-Json
        if ($parsedArgs -is [System.Management.Automation.PSCustomObject]) {
            foreach ($prop in $parsedArgs.PSObject.Properties) {
                $inputHash[$prop.Name] = $prop.Value
            }
        }

        return [PSCustomObject]@{
            Type      = "tool_call"
            ToolName  = $toolCall.function.name
            ToolInput = $inputHash
            ToolUseId = $toolCall.id
        }
    }
    else {
        $content = $choice.message.content
        return [PSCustomObject]@{
            Type    = "final_answer"
            Content = if ($content) { $content } else { "(empty response)" }
        }
    }
}
