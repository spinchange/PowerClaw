param(
    [ValidateSet('from-config', 'claude', 'openai', 'both')]
    [string]$Provider = 'from-config',

    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.json'),

    [string]$ClaudeModel,
    [string]$ClaudeApiKeyEnv = 'CLAUDE_API_KEY',

    [string]$OpenAiModel,
    [string]$OpenAiApiKeyEnv = 'OPENAI_API_KEY'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'client\providers\Send-ClaudeRequest.ps1')
. (Join-Path $repoRoot 'client\providers\Send-OpenAiRequest.ps1')

function Assert-Smoke {
    param(
        [string]$Label,
        [bool]$Condition
    )

    if (-not $Condition) {
        throw "Smoke assertion failed: $Label"
    }

    Write-Host "  [PASS] $Label" -ForegroundColor Green
}

function Invoke-SmokeWithRetry {
    param(
        [scriptblock]$Action,
        [string]$Label,
        [int]$MaxAttempts = 3
    )

    $delaySeconds = 10

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $Action
        }
        catch {
            $message = "$_"
            $isRetryable = (
                $message -match '^Rate limited by ' -or
                $message -match '^Rate limited\.' -or
                $message -match '^Claude API is overloaded'
            )

            if ((-not $isRetryable) -or $attempt -eq $MaxAttempts) {
                throw
            }

            Write-Host "  [Retry] $Label hit a transient provider limit. Waiting $delaySeconds seconds before retry $attempt/$($MaxAttempts - 1)..." -ForegroundColor Yellow
            Start-Sleep -Seconds $delaySeconds
            $delaySeconds *= 2
        }
    }
}

function Resolve-SmokeTargets {
    param(
        [string]$RequestedProvider,
        [string]$ResolvedConfigPath,
        [string]$ResolvedClaudeModel,
        [string]$ResolvedClaudeApiKeyEnv,
        [string]$ResolvedOpenAiModel,
        [string]$ResolvedOpenAiApiKeyEnv
    )

    $targets = @()

    if ($RequestedProvider -eq 'from-config') {
        if (-not (Test-Path -LiteralPath $ResolvedConfigPath)) {
            throw "Config not found at $ResolvedConfigPath"
        }

        $config = Get-Content -LiteralPath $ResolvedConfigPath -Raw | ConvertFrom-Json
        switch ($config.provider) {
            'claude' {
                $targets += [PSCustomObject]@{
                    Provider  = 'claude'
                    Model     = $config.model
                    ApiKeyEnv = $config.api_key_env
                }
            }
            'openai' {
                $targets += [PSCustomObject]@{
                    Provider  = 'openai'
                    Model     = $config.model
                    ApiKeyEnv = $config.api_key_env
                }
            }
            default {
                throw "Unsupported provider '$($config.provider)' in $ResolvedConfigPath"
            }
        }

        return $targets
    }

    if ($RequestedProvider -in @('claude', 'both')) {
        if (-not $ResolvedClaudeModel) {
            throw "Provide -ClaudeModel when running with -Provider claude or -Provider both."
        }

        $targets += [PSCustomObject]@{
            Provider  = 'claude'
            Model     = $ResolvedClaudeModel
            ApiKeyEnv = $ResolvedClaudeApiKeyEnv
        }
    }

    if ($RequestedProvider -in @('openai', 'both')) {
        if (-not $ResolvedOpenAiModel) {
            throw "Provide -OpenAiModel when running with -Provider openai or -Provider both."
        }

        $targets += [PSCustomObject]@{
            Provider  = 'openai'
            Model     = $ResolvedOpenAiModel
            ApiKeyEnv = $ResolvedOpenAiApiKeyEnv
        }
    }

    return $targets
}

function Invoke-ProviderFinalAnswerSmoke {
    param(
        [string]$SmokeProvider,
        [string]$Model,
        [string]$ApiKeyEnv
    )

    $config = [PSCustomObject]@{
        model       = $Model
        max_tokens  = 128
        api_key_env = $ApiKeyEnv
    }

    $messages = @(
        @{ role = 'user'; content = 'Reply with exactly: POWERCLAW_SMOKE_OK' }
    )

    $result = Invoke-SmokeWithRetry -Label "$SmokeProvider final-answer smoke" -Action {
        switch ($SmokeProvider) {
            'claude' {
                Send-ClaudeRequest `
                    -SystemPrompt 'Return a plain text final answer only.' `
                    -Messages $messages `
                    -ToolSchemas @() `
                    -Config $config
            }
            'openai' {
                Send-OpenAiRequest `
                    -SystemPrompt 'Return a plain text final answer only.' `
                    -Messages $messages `
                    -ToolSchemas @() `
                    -Config $config
            }
        }
    }

    Assert-Smoke "$SmokeProvider final-answer response type" ($result.Type -eq 'final_answer')
    Assert-Smoke "$SmokeProvider final-answer content" ($result.Content -match 'POWERCLAW_SMOKE_OK')
}

function Invoke-ProviderToolCallSmoke {
    param(
        [string]$SmokeProvider,
        [string]$Model,
        [string]$ApiKeyEnv
    )

    $config = [PSCustomObject]@{
        model       = $Model
        max_tokens  = 256
        api_key_env = $ApiKeyEnv
    }

    $toolSchemas = @(
        @{
            name = 'Get-SmokeStatus'
            description = 'Returns the smoke label for verification.'
            input_schema = @{
                type = 'object'
                properties = @{
                    Label = @{ type = 'string' }
                }
                required = @('Label')
                additionalProperties = $false
            }
        }
    )

    $messages = @(
        @{ role = 'user'; content = 'Call Get-SmokeStatus with Label set to POWERCLAW_SMOKE_TOOL. Do not answer directly.' }
    )

    $result = Invoke-SmokeWithRetry -Label "$SmokeProvider tool-call smoke" -Action {
        switch ($SmokeProvider) {
            'claude' {
                Send-ClaudeRequest `
                    -SystemPrompt 'Use the provided tool when the user explicitly asks for it.' `
                    -Messages $messages `
                    -ToolSchemas $toolSchemas `
                    -Config $config
            }
            'openai' {
                Send-OpenAiRequest `
                    -SystemPrompt 'Use the provided tool when the user explicitly asks for it.' `
                    -Messages $messages `
                    -ToolSchemas $toolSchemas `
                    -Config $config
            }
        }
    }

    Assert-Smoke "$SmokeProvider tool-call response type" ($result.Type -eq 'tool_call')
    Assert-Smoke "$SmokeProvider tool-call name" ($result.ToolName -eq 'Get-SmokeStatus')
    Assert-Smoke "$SmokeProvider tool-call label arg" ($result.ToolInput.Label -eq 'POWERCLAW_SMOKE_TOOL')
    Assert-Smoke "$SmokeProvider tool-call id present" (-not [string]::IsNullOrWhiteSpace($result.ToolUseId))
}

function Invoke-ProviderToolRoundtripSmoke {
    param(
        [string]$SmokeProvider,
        [string]$Model,
        [string]$ApiKeyEnv
    )

    $config = [PSCustomObject]@{
        model       = $Model
        max_tokens  = 256
        api_key_env = $ApiKeyEnv
    }

    $toolSchemas = @(
        @{
            name = 'Get-SmokeStatus'
            description = 'Returns the smoke label for verification.'
            input_schema = @{
                type = 'object'
                properties = @{
                    Label = @{ type = 'string' }
                }
                required = @('Label')
                additionalProperties = $false
            }
        }
    )

    $initialMessages = @(
        @{ role = 'user'; content = 'Call Get-SmokeStatus with Label set to POWERCLAW_SMOKE_TOOL. After you get the tool result, reply with exactly: POWERCLAW_TOOL_ROUNDTRIP_OK' }
    )

    $toolCallResult = Invoke-SmokeWithRetry -Label "$SmokeProvider roundtrip step 1 smoke" -Action {
        switch ($SmokeProvider) {
            'claude' {
                Send-ClaudeRequest `
                    -SystemPrompt 'Use the provided tool when the user explicitly asks for it. After receiving the tool result, answer with exactly the requested phrase and nothing else.' `
                    -Messages $initialMessages `
                    -ToolSchemas $toolSchemas `
                    -Config $config
            }
            'openai' {
                Send-OpenAiRequest `
                    -SystemPrompt 'Use the provided tool when the user explicitly asks for it. After receiving the tool result, answer with exactly the requested phrase and nothing else.' `
                    -Messages $initialMessages `
                    -ToolSchemas $toolSchemas `
                    -Config $config
            }
        }
    }

    Assert-Smoke "$SmokeProvider roundtrip step 1 response type" ($toolCallResult.Type -eq 'tool_call')
    Assert-Smoke "$SmokeProvider roundtrip step 1 tool name" ($toolCallResult.ToolName -eq 'Get-SmokeStatus')
    Assert-Smoke "$SmokeProvider roundtrip step 1 label arg" ($toolCallResult.ToolInput.Label -eq 'POWERCLAW_SMOKE_TOOL')

    $followUpMessages = @(
        $initialMessages[0]
        @{
            role = 'assistant'
            content = @(@{
                type  = 'tool_use'
                id    = $toolCallResult.ToolUseId
                name  = $toolCallResult.ToolName
                input = $toolCallResult.ToolInput
            })
        }
        @{
            role = 'user'
            content = @(@{
                type        = 'tool_result'
                tool_use_id = $toolCallResult.ToolUseId
                content     = 'Tool returned POWERCLAW_SMOKE_TOOL.'
            })
        }
    )

    $finalResult = Invoke-SmokeWithRetry -Label "$SmokeProvider roundtrip step 2 smoke" -Action {
        switch ($SmokeProvider) {
            'claude' {
                Send-ClaudeRequest `
                    -SystemPrompt 'After the provided tool result arrives, reply with exactly the requested phrase and nothing else.' `
                    -Messages $followUpMessages `
                    -ToolSchemas $toolSchemas `
                    -Config $config
            }
            'openai' {
                Send-OpenAiRequest `
                    -SystemPrompt 'After the provided tool result arrives, reply with exactly the requested phrase and nothing else.' `
                    -Messages $followUpMessages `
                    -ToolSchemas $toolSchemas `
                    -Config $config
            }
        }
    }

    Assert-Smoke "$SmokeProvider roundtrip step 2 response type" ($finalResult.Type -eq 'final_answer')
    Assert-Smoke "$SmokeProvider roundtrip final content" ($finalResult.Content -match 'POWERCLAW_TOOL_ROUNDTRIP_OK')
}

$targets = Resolve-SmokeTargets `
    -RequestedProvider $Provider `
    -ResolvedConfigPath $ConfigPath `
    -ResolvedClaudeModel $ClaudeModel `
    -ResolvedClaudeApiKeyEnv $ClaudeApiKeyEnv `
    -ResolvedOpenAiModel $OpenAiModel `
    -ResolvedOpenAiApiKeyEnv $OpenAiApiKeyEnv

Write-Host "Running live provider smoke checks..." -ForegroundColor Cyan

foreach ($target in $targets) {
    $apiKey = [System.Environment]::GetEnvironmentVariable($target.ApiKeyEnv)
    if (-not $apiKey) {
        throw "Missing required API key env var '$($target.ApiKeyEnv)' for provider '$($target.Provider)'."
    }

    Write-Host ""
    Write-Host "-- $($target.Provider) --" -ForegroundColor Yellow
    Write-Host "  model: $($target.Model)" -ForegroundColor DarkGray
    Write-Host "  api_key_env: $($target.ApiKeyEnv)" -ForegroundColor DarkGray

    Invoke-ProviderFinalAnswerSmoke `
        -SmokeProvider $target.Provider `
        -Model $target.Model `
        -ApiKeyEnv $target.ApiKeyEnv

    Invoke-ProviderToolCallSmoke `
        -SmokeProvider $target.Provider `
        -Model $target.Model `
        -ApiKeyEnv $target.ApiKeyEnv

    Invoke-ProviderToolRoundtripSmoke `
        -SmokeProvider $target.Provider `
        -Model $target.Model `
        -ApiKeyEnv $target.ApiKeyEnv
}

Write-Host ""
Write-Host "Live smoke checks passed." -ForegroundColor Green
