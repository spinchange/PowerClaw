BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:ModulePath = Join-Path $script:RepoRoot 'PowerCLAW.psd1'

    Import-Module $script:ModulePath -Force

    . (Join-Path $script:RepoRoot 'registry\Register-ClawTools.ps1')
    . (Join-Path $script:RepoRoot 'registry\ConvertTo-ToolSchema.ps1')
    . (Join-Path $script:RepoRoot 'client\providers\Send-OpenAiRequest.ps1')
    . (Join-Path $script:RepoRoot 'client\providers\Send-ClaudeRequest.ps1')
    . (Join-Path $script:RepoRoot 'tools\Get-TopProcesses.ps1')
    . (Join-Path $script:RepoRoot 'tools\Remove-Files.ps1')
}

Describe 'PowerClaw module' {
    It 'imports the module and exports Invoke-PowerClaw' {
        (Get-Command Invoke-PowerClaw -ErrorAction Stop).Name | Should -Be 'Invoke-PowerClaw'
    }
}

Describe 'Tool behavior' {
    It 'sorts process output by WorkingSet64 when SortBy=Memory' {
        $actual = @(Get-TopProcesses -SortBy Memory -Count 5)
        $expected = @(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5)

        $actual.Count | Should -Be 5
        @($actual.Id) | Should -Be @($expected.Id)
    }

    It 'deletes a literal-path file with wildcard characters in its name' {
        $tempFile = Join-Path $env:TEMP 'powerclaw pester [literal].txt'
        Set-Content -LiteralPath $tempFile -Value 'x'

        try {
            $result = Remove-Files -Paths @($tempFile)

            $result.FilesDeleted | Should -Be 1
            $result.Failed.Count | Should -Be 0
            $result.NotFound.Count | Should -Be 0
            $result.Deleted[0].Path | Should -Be $tempFile
        }
        finally {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Registry and schema' {
    It 'skips tools listed in disabled_tools even when also approved' {
        $tempRoot = Join-Path $env:TEMP 'powerclaw-pester-registry'
        $tempTools = Join-Path $tempRoot 'tools'
        $tempManifest = Join-Path $tempRoot 'tools-manifest.json'

        New-Item -ItemType Directory -Path $tempTools -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $tempTools 'Get-Alpha.ps1') -Value @'
function Get-Alpha {
    [CmdletBinding()]
    param()
    'alpha'
}
'@
        Set-Content -LiteralPath (Join-Path $tempTools 'Get-Beta.ps1') -Value @'
function Get-Beta {
    [CmdletBinding()]
    param()
    'beta'
}
'@
        Set-Content -LiteralPath $tempManifest -Value @'
{
  "approved_tools": ["Get-Alpha", "Get-Beta", "Get-Beta"],
  "disabled_tools": ["Get-Beta"]
}
'@

        try {
            $registered = @(Register-ClawTools -ToolsPath $tempTools -ManifestPath $tempManifest)

            @($registered | Where-Object Name -eq 'Get-Alpha').Count | Should -Be 1
            @($registered | Where-Object Name -eq 'Get-Beta').Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'emits schemas with additionalProperties disabled' {
        $schema = ConvertTo-ClaudeToolSchema ([PSCustomObject]@{
            Name = 'Get-Test'
            Description = 'test tool'
            Parameters = @(
                [PSCustomObject]@{ Name = 'Path'; Type = 'String'; Required = $true }
            )
        })

        $schema.input_schema.additionalProperties | Should -BeFalse
    }
}

Describe 'Providers' {
    It 'translates OpenAI requests and parses tool-call responses' {
        $env:POWERCLAW_TEST_OPENAI_KEY = 'test-openai-key'

        Mock Invoke-RestMethod {
            $script:OpenAiCall = @{
                Uri = $Uri
                Body = $Body | ConvertFrom-Json -Depth 20
                Headers = $Headers
            }

            [PSCustomObject]@{
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

        $result = Send-OpenAiRequest `
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

        $script:OpenAiCall.Uri | Should -Be 'https://api.openai.com/v1/chat/completions'
        $script:OpenAiCall.Body.messages[0].role | Should -Be 'system'
        $script:OpenAiCall.Body.messages[2].tool_calls[0].function.name | Should -Be 'Get-TopProcesses'
        $script:OpenAiCall.Body.messages[3].role | Should -Be 'tool'
        $result.Type | Should -Be 'tool_call'
        $result.ToolName | Should -Be 'Get-TopProcesses'
        $result.ToolInput.Count | Should -Be 5
    }

    It 'builds Claude payloads and converts tool_use input to a hashtable' {
        $env:POWERCLAW_TEST_CLAUDE_KEY = 'test-claude-key'

        Mock Invoke-RestMethod {
            $script:ClaudeCall = @{
                Uri = $Uri
                Body = $Body | ConvertFrom-Json -Depth 20
                Headers = $Headers
            }

            [PSCustomObject]@{
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

        $result = Send-ClaudeRequest `
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

        $script:ClaudeCall.Uri | Should -Be 'https://api.anthropic.com/v1/messages'
        $script:ClaudeCall.Body.system | Should -Be 'system prompt'
        $script:ClaudeCall.Body.tools[0].name | Should -Be 'Search-Files'
        $result.Type | Should -Be 'tool_call'
        $result.ToolName | Should -Be 'Search-Files'
        $result.ToolInput.Limit | Should -Be 10
    }
}
