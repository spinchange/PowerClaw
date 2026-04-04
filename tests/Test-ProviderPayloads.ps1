$pass = 0
$fail = 0

function Assert-True {
    param(
        [string]$Label,
        [bool]$Condition
    )

    if ($Condition) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [FAIL] $Label" -ForegroundColor Red
        $script:fail++
    }
}

$root = Split-Path $PSScriptRoot -Parent

Write-Host "`n-- OpenAI provider: request translation and tool-call parsing --" -ForegroundColor Cyan
$env:POWERCLAW_TEST_OPENAI_KEY = 'test-openai-key'

function Invoke-RestMethod {
    param(
        [string]$Uri,
        [string]$Method,
        [string]$Body,
        [string]$ContentType,
        [hashtable]$Headers,
        [int]$TimeoutSec
    )

    $script:LastOpenAiRequest = @{
        Uri         = $Uri
        Method      = $Method
        Body        = $Body | ConvertFrom-Json -Depth 20
        ContentType = $ContentType
        Headers     = $Headers
        TimeoutSec  = $TimeoutSec
    }

    return [PSCustomObject]@{
        choices = @(
            [PSCustomObject]@{
                finish_reason = 'tool_calls'
                message = [PSCustomObject]@{
                    tool_calls = @(
                        [PSCustomObject]@{
                            id = 'call_123'
                            function = [PSCustomObject]@{
                                name = 'Get-TopProcesses'
                                arguments = '{"SortBy":"CPU","Count":5}'
                            }
                        }
                    )
                }
            }
        )
    }
}

. (Join-Path $root 'client\providers\Send-OpenAiRequest.ps1')

$openAiResult = Send-OpenAiRequest `
    -SystemPrompt 'system prompt' `
    -Messages @(
        @{ role = 'user'; content = 'show me top processes' }
        @{
            role = 'assistant'
            content = @(@{
                type  = 'tool_use'
                id    = 'toolu_1'
                name  = 'Get-TopProcesses'
                input = @{ SortBy = 'Memory'; Count = 3 }
            })
        }
        @{
            role = 'user'
            content = @(@{
                type        = 'tool_result'
                tool_use_id = 'toolu_1'
                content     = 'tool output'
            })
        }
    ) `
    -ToolSchemas @(
        @{
            name = 'Get-TopProcesses'
            description = 'Gets top processes'
            input_schema = @{
                type = 'object'
                properties = @{
                    SortBy = @{ type = 'string' }
                    Count  = @{ type = 'integer' }
                }
            }
        }
    ) `
    -Config ([PSCustomObject]@{
        model = 'gpt-test'
        max_tokens = 256
        api_key_env = 'POWERCLAW_TEST_OPENAI_KEY'
    })

Assert-True "OpenAI endpoint is chat completions" (
    $script:LastOpenAiRequest.Uri -eq 'https://api.openai.com/v1/chat/completions'
)
Assert-True "OpenAI request starts with system message" (
    $script:LastOpenAiRequest.Body.messages[0].role -eq 'system'
)
Assert-True "Claude tool_use becomes OpenAI assistant tool_calls" (
    $script:LastOpenAiRequest.Body.messages[2].tool_calls[0].function.name -eq 'Get-TopProcesses'
)
Assert-True "Claude tool_result becomes OpenAI tool message" (
    $script:LastOpenAiRequest.Body.messages[3].role -eq 'tool'
)
Assert-True "OpenAI response parses back into canonical tool call" (
    $openAiResult.Type -eq 'tool_call' -and
    $openAiResult.ToolName -eq 'Get-TopProcesses' -and
    $openAiResult.ToolInput['Count'] -eq 5
)

Remove-Item Function:\Invoke-RestMethod

Write-Host "`n-- Claude provider: request payload and block parsing --" -ForegroundColor Cyan
$env:POWERCLAW_TEST_CLAUDE_KEY = 'test-claude-key'

function Invoke-RestMethod {
    param(
        [string]$Uri,
        [string]$Method,
        [string]$Body,
        [string]$ContentType,
        [hashtable]$Headers,
        [int]$TimeoutSec
    )

    $script:LastClaudeRequest = @{
        Uri         = $Uri
        Method      = $Method
        Body        = $Body | ConvertFrom-Json -Depth 20
        ContentType = $ContentType
        Headers     = $Headers
        TimeoutSec  = $TimeoutSec
    }

    return [PSCustomObject]@{
        stop_reason = 'tool_use'
        content = @(
            [PSCustomObject]@{
                type  = 'tool_use'
                id    = 'toolu_abc'
                name  = 'Search-Files'
                input = [PSCustomObject]@{
                    FileName = '*.log'
                    Limit    = 10
                }
            }
        )
    }
}

. (Join-Path $root 'client\providers\Send-ClaudeRequest.ps1')

$claudeResult = Send-ClaudeRequest `
    -SystemPrompt 'system prompt' `
    -Messages @(@{ role = 'user'; content = 'find logs' }) `
    -ToolSchemas @(
        @{
            name = 'Search-Files'
            description = 'Searches files'
            input_schema = @{
                type = 'object'
                properties = @{
                    FileName = @{ type = 'string' }
                    Limit    = @{ type = 'integer' }
                }
            }
        }
    ) `
    -Config ([PSCustomObject]@{
        model = 'claude-test'
        max_tokens = 256
        api_key_env = 'POWERCLAW_TEST_CLAUDE_KEY'
    })

Assert-True "Claude endpoint is messages API" (
    $script:LastClaudeRequest.Uri -eq 'https://api.anthropic.com/v1/messages'
)
Assert-True "Claude request includes system prompt" (
    $script:LastClaudeRequest.Body.system -eq 'system prompt'
)
Assert-True "Claude request includes tool schema" (
    $script:LastClaudeRequest.Body.tools[0].name -eq 'Search-Files'
)
Assert-True "Claude tool_use input converts to hashtable" (
    $claudeResult.Type -eq 'tool_call' -and
    $claudeResult.ToolName -eq 'Search-Files' -and
    $claudeResult.ToolInput['Limit'] -eq 10
)

Remove-Item Function:\Invoke-RestMethod
Remove-Item Env:\POWERCLAW_TEST_OPENAI_KEY -ErrorAction SilentlyContinue
Remove-Item Env:\POWERCLAW_TEST_CLAUDE_KEY -ErrorAction SilentlyContinue

Write-Host "`n-- Results: $pass passed, $fail failed --" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
