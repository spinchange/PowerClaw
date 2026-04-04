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

function Test-ClawHealthCheckGoal {
    param(
        [string]$UserGoal
    )

    if ([string]::IsNullOrWhiteSpace($UserGoal)) {
        return $false
    }

    return (
        $UserGoal -match '\bfull system health check\b' -or
        $UserGoal -match '\bmachine health\b' -or
        $UserGoal -match '\bfull health check\b' -or
        $UserGoal -match '\bdiagnostic\b' -or
        $UserGoal -match "\bwhat'?s eating my cpu\b" -or
        $UserGoal -match '\bcpu\b' -or
        $UserGoal -match '\bmemory\b' -or
        $UserGoal -match '\bram\b'
    )
}

function Test-ClawCleanupGoal {
    param(
        [string]$UserGoal
    )

    if ([string]::IsNullOrWhiteSpace($UserGoal)) {
        return $false
    }

    return (
        $UserGoal -match '\bdownloads\b' -or
        $UserGoal -match '\bbiggest files\b' -or
        $UserGoal -match '\blargest files\b' -or
        $UserGoal -match '\bcleanup\b' -or
        $UserGoal -match '\bclean up\b' -or
        $UserGoal -match '\bwhat should i clean\b' -or
        $UserGoal -match '\bwhat looks safe to remove\b'
    )
}

function Test-ClawDeleteTargetsWerePreviouslyEnumerated {
    param(
        [array]$Messages,
        [hashtable]$ToolInput
    )

    if (-not $ToolInput -or -not $ToolInput.ContainsKey('Paths')) {
        return $false
    }

    $requestedPaths = @($ToolInput.Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($requestedPaths.Count -eq 0) {
        return $false
    }

    $priorToolResultText = @($Messages | Where-Object {
        $_.role -eq 'user' -and
        $_.content -is [array] -and
        $_.content[0].type -eq 'tool_result'
    } | ForEach-Object {
        [string]$_.content[0].content
    }) -join "`n"

    if ([string]::IsNullOrWhiteSpace($priorToolResultText)) {
        return $false
    }

    foreach ($path in $requestedPaths) {
        if ($priorToolResultText -notmatch [regex]::Escape([string]$path)) {
            return $false
        }
    }

    return $true
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

function Show-ClawPlanPreview {
    param(
        [array]$PlanSteps,
        [string]$PlanSummary
    )

    if (-not $PlanSteps -or $PlanSteps.Count -eq 0) {
        Write-Host "`n[Plan] No tool steps were previewed." -ForegroundColor Yellow
        return
    }

    Write-Host "`n[Plan] Intended tool chain:" -ForegroundColor Cyan
    $index = 1
    foreach ($planStep in $PlanSteps) {
        Write-Host "  $index. $($planStep.Tool) [$($planStep.Risk)]" -ForegroundColor White
        if ($planStep.Args -and $planStep.Args.Count -gt 0) {
            foreach ($key in $planStep.Args.Keys) {
                Write-Host "     $key = $($planStep.Args[$key])" -ForegroundColor Gray
            }
        }
        $index++
    }

    if (-not [string]::IsNullOrWhiteSpace($PlanSummary)) {
        Write-Host ""
        Write-Host "  Summary: $PlanSummary" -ForegroundColor DarkGray
    }

    Write-Host "`nRun without -Plan to execute these steps for real." -ForegroundColor DarkGray
}

function Get-ClawStubToolResult {
    param(
        [string]$ToolName,
        [hashtable]$ToolInput,
        [string]$UserGoal
    )

    switch ($ToolName) {
        'Get-SystemSummary' {
            return @'
MachineName : DEMO-PC
OSVersion   : Windows 11 Pro
Uptime      : 4d 6h 12m
CPULoadPct  : 18
RAMUsedPct  : 63
TopByCPU    : pwsh (14.2 CPU), chrome (9.8 CPU), Code (4.1 CPU)
TopByMemory : chrome (1240 MB), Code (812 MB), pwsh (220 MB)
'@
        }
        'Get-TopProcesses' {
            $sortBy = if ($ToolInput -and $ToolInput.ContainsKey('SortBy')) { $ToolInput.SortBy } else { 'CPU' }
            if ($sortBy -eq 'Memory') {
                return @'
Name Id CPU MemoryMB
chrome 14120 88.7 1240.0
Code 22044 31.5 812.0
pwsh 19888 12.1 220.0
'@
            }

            return @'
Name Id CPU MemoryMB
pwsh 19888 114.2 220.0
chrome 14120 48.7 1240.0
Code 22044 22.4 812.0
'@
        }
        'Search-Files' {
            return @'
Name Path SizeMB DateModified
windows-iso-backup.zip C:\Users\chris\Downloads\windows-iso-backup.zip 5820.4 2026-03-28
obs-recording.mp4 C:\Users\chris\Downloads\obs-recording.mp4 2144.8 2026-04-02
driver-pack.exe C:\Users\chris\Downloads\driver-pack.exe 812.1 2026-02-11
'@
        }
        'Read-FileContent' {
            $path = if ($ToolInput -and $ToolInput.ContainsKey('Path')) { $ToolInput.Path } else { 'README.md' }
            return @"
Path       : $path
LinesShown : 12
Truncated  : False
Content    : provider=claude
             model=claude-sonnet-4-20250514
             api_key_env=CLAUDE_API_KEY
             max_steps=8
"@
        }
        'Fetch-WebPage' {
            $url = if ($ToolInput -and $ToolInput.ContainsKey('Url')) { $ToolInput.Url } else { 'https://example.com' }
            return @"
Url        : $url
Title      : Demo Page Summary
Characters : 1240
Truncated  : False
Content    : Top stories focus on browser automation, Windows tooling, and local AI workflows. The front page is heavy on product launches and release notes.
"@
        }
        'Get-DirectoryListing' {
            return @'
Name Length LastWriteTime PSIsContainer
Invoices false 2026-04-03
setup-notes.txt 8204 2026-04-02 False
gpu-driver.exe 402345678 2026-03-18 False
'@
        }
        default {
            return "[Stub tool result] Simulated output for $ToolName based on the request: $UserGoal"
        }
    }
}

function Get-ClawWorkflowPromptHints {
    param(
        [string]$UserGoal,
        [array]$Tools
    )

    if ([string]::IsNullOrWhiteSpace($UserGoal)) {
        return ''
    }

    $normalizedGoal = $UserGoal.ToLowerInvariant()
    $hints = [System.Collections.Generic.List[string]]::new()
    $availableToolNames = @($Tools | ForEach-Object {
        if ($_.Name) { [string]$_.Name }
    })

    if (
        Test-ClawHealthCheckGoal -UserGoal $UserGoal
    ) {
        $healthFollowUps = @(
            'Get-StorageStatus',
            'Get-NetworkStatus',
            'Get-ServiceStatus',
            'Get-EventLogEntries'
        ) | Where-Object { $_ -in $availableToolNames }

        $hints.Add('WORKFLOW HINT: For health-check or diagnostic prompts, it is good to combine a few complementary tools before answering. Prefer a concise chain across system summary, storage, network, services, or recent event issues when those signals materially improve the answer.')
        if ('Get-SystemSummary' -in $availableToolNames -and $healthFollowUps.Count -gt 0) {
            $hints.Add("WORKFLOW HINT: For a full health check, start with Get-SystemSummary and usually add at least one complementary tool before answering. Available follow-up signals here: $($healthFollowUps -join ', '). Do not stop after one tool if those extra signals would materially improve confidence.")
        }
        $hints.Add('WORKFLOW HINT: Speed matters. A normal health check should usually finish in 1 to 3 tool calls, not a long chain.')
        $hints.Add('WORKFLOW HINT: Prefer a fast first answer. Only add more tools when the earlier result suggests something abnormal, ambiguous, or worth confirming.')
        $hints.Add('WORKFLOW HINT: For most health checks, prefer system summary first, then storage or event issues if needed. Only pull services or network details when the earlier signals suggest a real problem there.')
        $hints.Add('WORKFLOW HINT: For a health check final answer, synthesize into a short operator summary: overall status first, then the most important issues, then concrete next checks if needed.')
        $hints.Add('WORKFLOW HINT: Health-check answers should feel like an operator readout, not a tool dump. Lead with whether the machine looks healthy, degraded, or needs attention.')
        $hints.Add('WORKFLOW HINT: Health-check final answers should usually follow this structure: Overall status, Key findings, Why it matters, Next checks. If nothing looks urgent, say that explicitly instead of sounding alarmed.')
        $hints.Add('WORKFLOW HINT: Do not end a health check with a raw metric dump. Interpret the CPU, memory, storage, network, or service signals into a short operational judgment.')
    }

    if (Test-ClawCleanupGoal -UserGoal $UserGoal) {
        $cleanupContextTools = @(
            'Get-DirectoryListing',
            'Read-FileContent'
        ) | Where-Object { $_ -in $availableToolNames }

        $hints.Add('WORKFLOW HINT: For cleanup and biggest-file prompts, it is acceptable to chain discovery plus context. Find the likely cleanup targets first, then summarize what they are, how large they are, and what you would review before deletion.')
        if ('Search-Files' -in $availableToolNames) {
            $hints.Add('WORKFLOW HINT: For a normal cleanup prompt, start with Search-Files or another broad discovery tool so the first answer arrives quickly.')
        }
        if ($cleanupContextTools.Count -gt 0) {
            $hints.Add("WORKFLOW HINT: Add context tools such as $($cleanupContextTools -join ', ') only when the first discovery result leaves real ambiguity about what the files are or whether they are worth reviewing.")
        }
        $hints.Add('WORKFLOW HINT: Speed matters here too. A normal cleanup answer should usually finish in 1 to 2 tool calls.')
        $hints.Add('WORKFLOW HINT: Cleanup answers should not stop at raw listings. Include a short recommendation section such as what looks safe to review, what is ambiguous, and whether the user should preview or confirm anything.')
        $hints.Add('WORKFLOW HINT: Cleanup final answers should usually follow this order: what I found, what looks worth reviewing, what is ambiguous or risky, then the next safe action.')
        $hints.Add('WORKFLOW HINT: Do not recommend deletion just because a file is large. Distinguish large-but-likely-intentional files from obvious disposable installers, duplicates, or stale downloads when the evidence supports that distinction.')
        $hints.Add('WORKFLOW HINT: If the evidence is thin, say "worth reviewing" rather than "safe to delete."')
    }

    if (
        $normalizedGoal -match '\bread\b' -or
        $normalizedGoal -match '\bconfig\b' -or
        $normalizedGoal -match '\blog\b' -or
        $normalizedGoal -match '\bmanifest\b' -or
        $normalizedGoal -match '\breadme\b' -or
        $normalizedGoal -match 'https?://'
    ) {
        $hints.Add('WORKFLOW HINT: For read, config, log, and webpage investigation prompts, start with a plain-English summary before details.')
        $hints.Add('WORKFLOW HINT: After the summary, pull out the specific settings, warnings, or takeaways that matter. If the content suggests an action, end with the implication or next step.')
    }

    return ($hints -join "`n")
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

    $workflowHints = Get-ClawWorkflowPromptHints -UserGoal $UserGoal -Tools $Tools
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
- When the user's workflow clearly needs synthesis across multiple signals, a short multi-tool chain is better than a thin single-tool answer.
- In a final answer, interpret the tool results for the user. Do not just restate tool names, raw headings, or a loose metric dump.

ENVIRONMENT:
- Username: $env:USERNAME
- Home: $env:USERPROFILE
- Desktop: $env:USERPROFILE\Desktop
- Downloads: $env:USERPROFILE\Downloads
- Documents: $env:USERPROFILE\Documents
- Computer: $env:COMPUTERNAME

$workflowHints
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
    $isHealthCheckGoal = Test-ClawHealthCheckGoal -UserGoal $UserGoal
    $isCleanupGoal = Test-ClawCleanupGoal -UserGoal $UserGoal
    $planSteps = [System.Collections.Generic.List[object]]::new()
    $planSummary = $null
    $maxPlanPreviewSteps = [Math]::Min($MaxSteps, 3)
    $maxHealthCheckToolCalls = 3
    $executedReadOnlyToolCount = 0

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
            if ($Plan) {
                $planSummary = $response.Content
                Show-ClawPlanPreview -PlanSteps @($planSteps) -PlanSummary $planSummary
                Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                    Event       = 'plan_preview'
                    Step        = $step
                    Outcome     = 'previewed'
                    StepCount   = $planSteps.Count
                    PlanSummary = $planSummary
                }
                return $null
            }

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

            if (
                -not $Plan -and
                $isHealthCheckGoal -and
                $tool.Risk -eq 'ReadOnly' -and
                $executedReadOnlyToolCount -ge $maxHealthCheckToolCalls
            ) {
                $toolResult = "Health-check latency budget reached: you already used $executedReadOnlyToolCount read-only tools for this health check. Answer now from the signals already gathered unless the user explicitly asks for deeper investigation."
                Write-Host "[Latency] Health-check tool budget reached; asking model to answer from current signals." -ForegroundColor Yellow
                Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                    Event      = 'tool_skipped'
                    Step       = $step
                    Outcome    = 'blocked'
                    Tool       = $toolName
                    ToolUseId  = $response.ToolUseId
                    Reason     = 'health_check_latency_budget_reached'
                    UserGoal   = $UserGoal
                    ToolCount  = $executedReadOnlyToolCount
                }
                $messages = Add-ClawToolResultTurn -Messages $messages -ToolUseId $response.ToolUseId -ToolName $toolName -ToolInput $toolInput -Content $toolResult
                continue
            }

            if (
                -not $Plan -and
                $isCleanupGoal -and
                $tool.Risk -eq 'ReadOnly' -and
                $executedReadOnlyToolCount -ge 2
            ) {
                $toolResult = "Cleanup latency budget reached: you already used $executedReadOnlyToolCount read-only tools for this cleanup request. Answer now from the files and context already gathered unless the user explicitly asks for deeper inspection."
                Write-Host "[Latency] Cleanup tool budget reached; asking model to answer from current signals." -ForegroundColor Yellow
                Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                    Event      = 'tool_skipped'
                    Step       = $step
                    Outcome    = 'blocked'
                    Tool       = $toolName
                    ToolUseId  = $response.ToolUseId
                    Reason     = 'cleanup_latency_budget_reached'
                    UserGoal   = $UserGoal
                    ToolCount  = $executedReadOnlyToolCount
                }
                $messages = Add-ClawToolResultTurn -Messages $messages -ToolUseId $response.ToolUseId -ToolName $toolName -ToolInput $toolInput -Content $toolResult
                continue
            }

            if ($Plan) {
                $planSteps.Add([PSCustomObject]@{
                    Tool = $toolName
                    Risk = $tool.Risk
                    Args = $toolInput
                }) | Out-Null

                $planToolResult = "Plan preview only: $toolName was not executed. Continue by previewing the next intended step or return a concise plan summary based on the intended chain so far. Do not assume real tool output."
                $messages = Add-ClawToolResultTurn -Messages $messages -ToolUseId $response.ToolUseId -ToolName $toolName -ToolInput $toolInput -Content $planToolResult

                if ($planSteps.Count -ge $maxPlanPreviewSteps) {
                    Show-ClawPlanPreview -PlanSteps @($planSteps) -PlanSummary $null
                    Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                        Event     = 'plan_preview'
                        Step      = $step
                        Outcome   = 'previewed'
                        StepCount = $planSteps.Count
                        Reason    = 'plan_step_limit_reached'
                    }
                    return $null
                }

                continue
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

                if (
                    $toolName -eq 'Remove-Files' -and
                    -not (Test-ClawDeleteTargetsWerePreviouslyEnumerated -Messages $messages -ToolInput $toolInput)
                ) {
                    $toolResult = "Blocked by write policy: Remove-Files may only run on exact paths that were already shown in earlier read-only results during this request. First enumerate the candidate files with a read-only tool, then ask again with those same full paths."
                    Write-Host "[Blocked] $toolName requires evidence-backed file targets before deletion." -ForegroundColor Yellow
                    Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                        Event      = 'tool_skipped'
                        Step       = $step
                        Outcome    = 'blocked'
                        Tool       = $toolName
                        ToolUseId  = $response.ToolUseId
                        Reason     = 'write_targets_not_previously_enumerated'
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
                if ($UseStub) {
                    $toolResult = Get-ClawStubToolResult -ToolName $toolName -ToolInput $toolInput -UserGoal $UserGoal
                    $toolStatus = 'success'
                }
                else {
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
                }

                $durationMs = [int]((Get-Date) - $startedAt).TotalMilliseconds
                if ($tool.Risk -eq 'ReadOnly' -and $toolStatus -eq 'success') {
                    $executedReadOnlyToolCount++
                }
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
