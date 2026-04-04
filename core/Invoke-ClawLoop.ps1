# core/Invoke-ClawLoop.ps1

function Write-ClawLoopLogEntry {
    param(
        [string]$LogPath,
        [hashtable]$Entry
    )

    if (-not $LogPath) {
        return
    }

    $safeEntry = @{}
    foreach ($key in $Entry.Keys) {
        $value = $Entry[$key]
        if ($null -eq $value) {
            $safeEntry[$key] = $null
            continue
        }

        if ($value -is [string] -or $value -is [ValueType] -or $value -is [bool]) {
            $safeEntry[$key] = $value
            continue
        }

        $safeEntry[$key] = $value
    }

    $safeEntry.SchemaVersion = '1'
    $safeEntry.Timestamp = Get-Date -Format 'o'
    Add-Content -Path $LogPath -Value ($safeEntry | ConvertTo-Json -Depth 6 -Compress) -ErrorAction SilentlyContinue
}

function Get-ClawToolCallFingerprint {
    param(
        [string]$ToolName,
        [hashtable]$ToolInput
    )

    $normalizedInput = if ($ToolInput) {
        $ordered = [ordered]@{}
        foreach ($key in ($ToolInput.Keys | Sort-Object)) {
            $ordered[$key] = $ToolInput[$key]
        }
        $ordered | ConvertTo-Json -Depth 10 -Compress
    } else {
        '{}'
    }

    return "$ToolName|$normalizedInput"
}

function Test-ClawExplicitWriteIntent {
    param(
        [string]$UserGoal
    )

    if ([string]::IsNullOrWhiteSpace($UserGoal)) {
        return $false
    }

    $negativePatterns = @(
        '\bsafe to (?:delete|remove)\b',
        '\bwhat (?:looks|seems) safe to (?:delete|remove)\b',
        '\bshould i (?:delete|remove)\b',
        '\bcan i (?:delete|remove)\b',
        '\bwhat can i (?:delete|remove)\b',
        '\bwhat should i (?:delete|remove)\b'
    )

    foreach ($pattern in $negativePatterns) {
        if ($UserGoal -match $pattern) {
            return $false
        }
    }

    $patterns = @(
        '\bdelete\b',
        '\bremove\b',
        '\berase\b',
        '\bclean\s+up\b',
        '\bclean\b',
        '\btrash\b',
        '\brecycle\b',
        '\bmove\s+to\s+recycle\b',
        '\bpermanent(?:ly)?\s+delete\b',
        '\bpurge\b'
    )

    foreach ($pattern in $patterns) {
        if ($UserGoal -match $pattern) {
            return $true
        }
    }

    return $false
}

function Add-ClawToolResultTurn {
    param(
        [array]$Messages,
        [string]$ToolUseId,
        [string]$ToolName,
        [hashtable]$ToolInput,
        [string]$Content
    )

    $Messages += @{
        role = "assistant"
        content = @(@{
            type  = "tool_use"
            id    = $ToolUseId
            name  = $ToolName
            input = $ToolInput
        })
    }
    $Messages += @{
        role = "user"
        content = @(@{
            type        = "tool_result"
            tool_use_id = $ToolUseId
            content     = $Content
        })
    }

    return ,$Messages
}

function Invoke-ClawLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserGoal,

        [array]$Tools,

        [object]$Config,

        [int]$MaxSteps = 8,

        [switch]$DryRun,

        [switch]$Plan,

        [switch]$UseStub
    )

    $systemPrompt = @"
You are PowerClaw, a Windows automation agent running on PowerShell 7.
You have access to the provided tools. Use them to accomplish the user's goal.
When you have enough information to answer, respond with a plain text final answer.
RULES:
- Only call the provided tools. Never generate raw PowerShell.
- Prefer read-only operations unless the user explicitly requests changes.
- If a tool fails, report the error as your final answer. Do not retry with a different path or arguments.
- Use the minimum number of tool calls necessary. One tool call is usually enough — answer immediately from its output rather than gathering more data from additional tools.
- Do not call the same tool twice with different parameters unless the user explicitly asked for multiple queries.

ENVIRONMENT:
- Username: $env:USERNAME
- Home: $env:USERPROFILE
- Desktop: $env:USERPROFILE\Desktop
- Downloads: $env:USERPROFILE\Downloads
- Documents: $env:USERPROFILE\Documents
- Computer: $env:COMPUTERNAME
"@

    if (-not $Config) {
        $Config = Get-Content (Join-Path $PSScriptRoot '..\config.json') -Raw | ConvertFrom-Json
    }
    $maxOutputChars = [int]$Config.max_output_chars
    $logPath = Join-Path $PSScriptRoot "..\$($Config.log_file)"

    $toolSchemas = $Tools | ForEach-Object { ConvertTo-ClaudeToolSchema $_ }
    $messages = @(@{ role = "user"; content = $UserGoal })
    $seenToolCalls = @{}
    $userExplicitlyRequestedWrite = Test-ClawExplicitWriteIntent -UserGoal $UserGoal

    for ($step = 1; $step -le $MaxSteps; $step++) {
        Write-Host "`n[Step $step/$MaxSteps]" -ForegroundColor DarkGray
        Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
            Event        = 'step_start'
            Outcome      = 'started'
            Step         = $step
            MaxSteps     = $MaxSteps
            UserGoal     = $UserGoal
            MessageCount = $messages.Count
        }

        $response  = $null
        $retryWait = 10
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $response = Send-ClawRequest `
                    -SystemPrompt $systemPrompt `
                    -Messages $messages `
                    -ToolSchemas $toolSchemas `
                    -UseStub:$UseStub
                break   # success — exit retry loop
            }
            catch {
                $msg = "$_"
                if ($msg -match 'rate limit|429') {
                    if ($attempt -lt 3) {
                        Write-Host "[Rate limited] Waiting ${retryWait}s before retry $attempt/2..." -ForegroundColor Yellow
                        Start-Sleep -Seconds $retryWait
                        $retryWait *= 2   # 10s → 20s
                    } else {
                        Write-Host "[Error] Rate limited after 3 attempts. Wait a minute and try again." -ForegroundColor Red
                    }
                } elseif ($msg -match 'timed out|timeout') {
                    Write-Host "[Error] Claude didn't respond in 60s. Check your connection or try again." -ForegroundColor Red
                    break
                } elseif ($msg -match 'Invalid API key|401') {
                    Write-Host "[Error] Invalid API key. Check `$env:$((Get-Content (Join-Path $PSScriptRoot '..\config.json') | ConvertFrom-Json).api_key_env)." -ForegroundColor Red
                    break
                } else {
                    Write-Host "[Error] LLM call failed: $msg" -ForegroundColor Red
                    break
                }
            }
        }
        if (-not $response) {
            Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                Event  = 'loop_abort'
                Outcome = 'aborted'
                Step   = $step
                Reason = 'no_model_response'
            }
            return $null
        }

        Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
            Event        = 'model_response'
            Outcome      = 'received'
            Step         = $step
            ResponseType = $response.Type
            ToolName     = $response.ToolName
            ToolUseId    = $response.ToolUseId
        }

        # ── Final answer ──
        if ($response.Type -eq "final_answer") {
            Write-Host "`n[Answer]" -ForegroundColor Green
            Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                Event   = 'final_answer'
                Step    = $step
                Outcome = 'final_answer'
                Preview = if ($response.Content) { "$($response.Content)".Substring(0, [Math]::Min(200, "$($response.Content)".Length)) } else { '' }
            }
            return $response.Content
        }

        # ── Tool call ──
        if ($response.Type -eq "tool_call") {
            $toolName  = $response.ToolName
            $toolInput = $response.ToolInput
            $tool      = $Tools | Where-Object { $_.Name -eq $toolName }
            $toolCallFingerprint = Get-ClawToolCallFingerprint -ToolName $toolName -ToolInput $toolInput

            Write-Host "[Model] Requested $toolName" -ForegroundColor DarkGray
            Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                Event            = 'tool_requested'
                Outcome          = 'requested'
                Step             = $step
                Tool             = $toolName
                ToolUseId        = $response.ToolUseId
                Args             = $toolInput
                ToolCallIdentity = $toolCallFingerprint
            }

            if (-not $tool) {
                $availableTools = @($Tools | Select-Object -ExpandProperty Name)
                $toolResult = "Error: tool '$toolName' is not available in the approved registry. Available tools: $($availableTools -join ', '). Choose one of the available tools or answer from what you already know."
                Write-Host "[Error] Model requested '$toolName' but it's not in your approved tools." -ForegroundColor Red
                Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                    Event          = 'tool_unavailable'
                    Step           = $step
                    Outcome        = 'rejected'
                    Tool           = $toolName
                    ToolUseId      = $response.ToolUseId
                    AvailableTools = $availableTools
                }
                $messages = Add-ClawToolResultTurn -Messages $messages -ToolUseId $response.ToolUseId -ToolName $toolName -ToolInput $toolInput -Content $toolResult
                continue
            }

            if ($seenToolCalls.ContainsKey($toolCallFingerprint)) {
                $toolResult = "Error: repeated tool call detected for '$toolName' with the same arguments. Do not call the same tool again with identical input. Use the earlier result to answer, or explain why the task cannot continue."
                Write-Host "[Warning] Repeated tool call blocked for $toolName with identical arguments." -ForegroundColor Yellow
                Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                    Event            = 'tool_rejected'
                    Step             = $step
                    Outcome          = 'rejected'
                    Tool             = $toolName
                    ToolUseId        = $response.ToolUseId
                    Reason           = 'repeated_identical_tool_call'
                    ToolCallIdentity = $toolCallFingerprint
                }

                $messages = Add-ClawToolResultTurn -Messages $messages -ToolUseId $response.ToolUseId -ToolName $toolName -ToolInput $toolInput -Content $toolResult
                continue
            }

            $seenToolCalls[$toolCallFingerprint] = $true

            # ── Plan mode: print step 1 and stop ──
            # Note: -Plan shows only the first action Claude would take, not a full
            # multi-step plan. For prompts that require chaining, only step 1 is shown.
            if ($Plan) {
                Write-Host "`n[Plan] First action the model would take:" -ForegroundColor Cyan
                Write-Host "  Tool: $toolName" -ForegroundColor White
                Write-Host "  Risk: $($tool.Risk)" -ForegroundColor $(if ($tool.Risk -eq 'ReadOnly') { 'Green' } else { 'Yellow' })
                Write-Host "  Args:" -ForegroundColor White
                foreach ($key in $toolInput.Keys) {
                    Write-Host "    $key = $($toolInput[$key])" -ForegroundColor Gray
                }
                Write-Host "`nRun without -Plan to execute all steps." -ForegroundColor DarkGray
                Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                    Event     = 'plan_preview'
                    Step      = $step
                    Outcome   = 'previewed'
                    Tool      = $toolName
                    ToolUseId = $response.ToolUseId
                    Risk      = $tool.Risk
                    Args      = $toolInput
                }
                return $null
            }

            # Safety check
            if ($tool.Risk -ne 'ReadOnly') {
                if (-not $userExplicitlyRequestedWrite) {
                    $toolResult = "Blocked by write policy: the user goal did not explicitly ask for a destructive change. Ask for confirmation in plain language first, or continue with read-only investigation."
                    Write-Host "[Blocked] $toolName requires an explicit user request for changes." -ForegroundColor Yellow
                    Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                        Event      = 'tool_skipped'
                        Step       = $step
                        Outcome    = 'blocked'
                        Tool       = $toolName
                        ToolUseId  = $response.ToolUseId
                        Reason     = 'write_policy_blocked'
                        Risk       = $tool.Risk
                        Args       = $toolInput
                        UserGoal   = $UserGoal
                    }
                    $messages = Add-ClawToolResultTurn -Messages $messages -ToolUseId $response.ToolUseId -ToolName $toolName -ToolInput $toolInput -Content $toolResult
                    continue
                }

                if ($DryRun) {
                    Write-Host "[DryRun] Would call $toolName with:" -ForegroundColor Yellow
                    Write-Host ($toolInput | ConvertTo-Json -Depth 3)
                    $toolResult = "(dry run — not executed)"
                    Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                        Event     = 'tool_skipped'
                        Step      = $step
                        Outcome   = 'dry_run'
                        Tool      = $toolName
                        ToolUseId = $response.ToolUseId
                        Reason    = 'dry_run'
                        Risk      = $tool.Risk
                        Args      = $toolInput
                    }
                }
                else {
                    $confirmToken = $toolName.ToUpperInvariant()
                    Write-Host "[Confirm] $toolName ($($tool.Risk) risk)" -ForegroundColor Yellow
                    Write-Host "  Args: $($toolInput | ConvertTo-Json -Depth 3 -Compress)"
                    Write-Host "  Type $confirmToken to confirm. Anything else cancels." -ForegroundColor Yellow
                    $confirm = Read-Host "  Confirmation"
                    if ($confirm -cne $confirmToken) {
                        $toolResult = "User declined to run $toolName. Confirmation token '$confirmToken' was not provided."
                        Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                            Event             = 'tool_skipped'
                            Step              = $step
                            Outcome           = 'declined'
                            Tool              = $toolName
                            ToolUseId         = $response.ToolUseId
                            Reason            = 'confirmation_declined'
                            Risk              = $tool.Risk
                            Args              = $toolInput
                            ConfirmationToken = $confirmToken
                            ConfirmationInput = $confirm
                        }
                        $messages = Add-ClawToolResultTurn -Messages $messages -ToolUseId $response.ToolUseId -ToolName $toolName -ToolInput $toolInput -Content $toolResult
                        continue
                    }

                    Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                        Event             = 'tool_confirmed'
                        Step              = $step
                        Outcome           = 'confirmed'
                        Tool              = $toolName
                        ToolUseId         = $response.ToolUseId
                        Risk              = $tool.Risk
                        Args              = $toolInput
                        ConfirmationToken = $confirmToken
                    }
                }
            }

            # Execute
            if (-not $DryRun -or $tool.Risk -eq 'ReadOnly') {
                Write-Host "[Executing] $toolName" -ForegroundColor Cyan
                $startedAt = Get-Date
                try {
                    $splatArgs = @{}
                    foreach ($key in $toolInput.Keys) {
                        $splatArgs[$key] = $toolInput[$key]
                    }
                    $toolResult = & $tool.ScriptBlock @splatArgs | Out-String
                    if ($toolResult.Length -gt $maxOutputChars) {
                        Write-Warning "Output truncated from $($toolResult.Length) to $maxOutputChars chars"
                        $toolResult = $toolResult.Substring(0, $maxOutputChars) + "`n... (truncated — output limit reached. Summarize what you have above as your final answer. Do not call this tool again.)"
                    }
                    $toolStatus = 'success'
                }
                catch {
                    $toolResult = "${toolName} failed: $_. Do not retry — report this error as your final answer."
                    Write-Host "[Error] ${toolName} failed: $_" -ForegroundColor Red
                    $toolStatus = 'error'
                }

                $durationMs = [int]((Get-Date) - $startedAt).TotalMilliseconds
            }

            Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                Event         = 'tool_result'
                Step          = $step
                Outcome       = if ($tool.Risk -eq 'ReadOnly') { $toolStatus } else { "executed_$toolStatus" }
                Tool          = $toolName
                ToolUseId     = $response.ToolUseId
                Args          = $toolInput
                Risk          = $tool.Risk
                Status        = $toolStatus
                ResultLen     = if ($toolResult) { $toolResult.Length } else { 0 }
                DryRun        = $DryRun.IsPresent
                DurationMs    = $durationMs
                ResultPreview = if ($toolResult) { $toolResult.Substring(0, [Math]::Min(200, $toolResult.Length)) } else { '' }
            }

            # Feed result back — format for Claude tool_result
            $messages = Add-ClawToolResultTurn -Messages $messages -ToolUseId $response.ToolUseId -ToolName $toolName -ToolInput $toolInput -Content $toolResult

            # Brief pause between steps to avoid rate limiting on rapid multi-tool prompts
            Start-Sleep -Seconds 1
        }
    }

    Write-Host "[Warning] Reached $MaxSteps steps without a final answer. Try a simpler prompt or increase max_steps in config.json." -ForegroundColor Yellow
    Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
        Event    = 'loop_abort'
        Step     = $MaxSteps
        Outcome  = 'aborted'
        Reason   = 'max_steps_reached'
        MaxSteps = $MaxSteps
    }
    return $null
}
