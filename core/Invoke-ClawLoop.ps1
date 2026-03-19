# core/Invoke-ClawLoop.ps1

function Invoke-ClawLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserGoal,

        [array]$Tools,

        [int]$MaxSteps = 8,

        [switch]$DryRun,

        [switch]$Plan,

        [switch]$UseStub
    )

    $systemPrompt = @"
You are PowerCLAW, a Windows automation agent running on PowerShell 7.
You have access to the provided tools. Use them to accomplish the user's goal.
When you have enough information to answer, respond with a plain text final answer.
RULES:
- Only call the provided tools. Never generate raw PowerShell.
- Prefer read-only operations unless the user explicitly requests changes.
- If a tool fails, report the error as your final answer. Do not retry with a different path or arguments.

ENVIRONMENT:
- Username: $env:USERNAME
- Home: $env:USERPROFILE
- Desktop: $env:USERPROFILE\Desktop
- Downloads: $env:USERPROFILE\Downloads
- Documents: $env:USERPROFILE\Documents
- Computer: $env:COMPUTERNAME
"@

    $toolSchemas = $Tools | ForEach-Object { ConvertTo-ClaudeToolSchema $_ }
    $messages = @(@{ role = "user"; content = $UserGoal })

    for ($step = 1; $step -le $MaxSteps; $step++) {
        Write-Host "`n[Step $step/$MaxSteps]" -ForegroundColor DarkGray

        try {
            $response = Send-ClawRequest `
                -SystemPrompt $systemPrompt `
                -Messages $messages `
                -ToolSchemas $toolSchemas `
                -UseStub:$UseStub
        }
        catch {
            $msg = "$_"
            if ($msg -match 'timed out|timeout') {
                Write-Host "[Error] Claude didn't respond in 60s. Check your connection or try again." -ForegroundColor Red
            } elseif ($msg -match 'rate limit|429') {
                Write-Host "[Error] Rate limited by Claude API. Wait a moment and retry." -ForegroundColor Red
            } elseif ($msg -match 'Invalid API key|401') {
                Write-Host "[Error] Invalid API key. Check `$env:$((Get-Content (Join-Path $PSScriptRoot '..\config.json') | ConvertFrom-Json).api_key_env)." -ForegroundColor Red
            } else {
                Write-Host "[Error] LLM call failed: $msg" -ForegroundColor Red
            }
            return $null
        }

        # ── Final answer ──
        if ($response.Type -eq "final_answer") {
            Write-Host "`n[Answer]" -ForegroundColor Green
            return $response.Content
        }

        # ── Tool call ──
        if ($response.Type -eq "tool_call") {
            $toolName  = $response.ToolName
            $toolInput = $response.ToolInput
            $tool      = $Tools | Where-Object { $_.Name -eq $toolName }

            if (-not $tool) {
                Write-Host "[Error] Claude requested '$toolName' but it's not in your approved tools. Check tools-manifest.json." -ForegroundColor Red
                $messages += @{ role = "assistant"; content = ($response | ConvertTo-Json -Depth 5 -Compress) }
                $messages += @{ role = "user"; content = "Error: tool '$toolName' is not available." }
                continue
            }

            # ── Plan mode: print what would run and stop ──
            if ($Plan) {
                Write-Host "`n[Plan]" -ForegroundColor Cyan
                Write-Host "  Tool: $toolName" -ForegroundColor White
                Write-Host "  Risk: $($tool.Risk)" -ForegroundColor $(if ($tool.Risk -eq 'ReadOnly') { 'Green' } else { 'Yellow' })
                Write-Host "  Args:" -ForegroundColor White
                foreach ($key in $toolInput.Keys) {
                    Write-Host "    $key = $($toolInput[$key])" -ForegroundColor Gray
                }
                Write-Host "`nRun without -Plan to execute." -ForegroundColor DarkGray
                return $null
            }

            # Safety check
            if ($tool.Risk -ne 'ReadOnly') {
                if ($DryRun) {
                    Write-Host "[DryRun] Would call $toolName with:" -ForegroundColor Yellow
                    Write-Host ($toolInput | ConvertTo-Json -Depth 3)
                    $toolResult = "(dry run — not executed)"
                }
                else {
                    Write-Host "[Confirm] $toolName ($($tool.Risk) risk)" -ForegroundColor Yellow
                    Write-Host "  Args: $($toolInput | ConvertTo-Json -Depth 3 -Compress)"
                    $confirm = Read-Host "  Proceed? (Y/N)"
                    if ($confirm -ne 'Y') {
                        $messages += @{ role = "user"; content = "User declined to run $toolName." }
                        continue
                    }
                }
            }

            # Execute
            if (-not $DryRun -or $tool.Risk -eq 'ReadOnly') {
                Write-Host "[Executing] $toolName" -ForegroundColor Cyan
                try {
                    $splatArgs = @{}
                    foreach ($key in $toolInput.Keys) {
                        $splatArgs[$key] = $toolInput[$key]
                    }
                    $toolResult = & $tool.ScriptBlock @splatArgs | Out-String
                    if ($toolResult.Length -gt 12000) {
                        Write-Warning "Output truncated from $($toolResult.Length) to 12000 chars"
                        $toolResult = $toolResult.Substring(0, 12000) + "`n... (truncated)"
                    }
                }
                catch {
                    $toolResult = "${toolName} failed: $_. Do not retry — report this error as your final answer."
                    Write-Host "[Error] ${toolName} failed: $_" -ForegroundColor Red
                }
            }

            # Log (simple append-only)
            $logEntry = @{
                Timestamp = (Get-Date -Format 'o')
                Step      = $step
                Tool      = $toolName
                Args      = $toolInput
                Risk      = $tool.Risk
                ResultLen = $toolResult.Length
                DryRun    = $DryRun.IsPresent
            } | ConvertTo-Json -Depth 3 -Compress
            $logPath = Join-Path $PSScriptRoot '..\powerclaw.log'
            Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue

            # Feed result back — format for Claude tool_result
            $messages += @{
                role = "assistant"
                content = @(@{
                    type  = "tool_use"
                    id    = $response.ToolUseId
                    name  = $toolName
                    input = $toolInput
                })
            }
            $messages += @{
                role = "user"
                content = @(@{
                    type        = "tool_result"
                    tool_use_id = $response.ToolUseId
                    content     = $toolResult
                })
            }
        }
    }

    Write-Host "[Warning] Reached $MaxSteps steps without a final answer. Try a simpler prompt or increase max_steps in config.json." -ForegroundColor Yellow
    return $null
}
