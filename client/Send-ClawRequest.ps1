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
        function Get-StubAvailableToolNames {
            param([array]$ToolSchemas)

            @($ToolSchemas | ForEach-Object {
                if ($_.name) { $_.name }
            })
        }

        function Test-StubToolAvailable {
            param(
                [string]$ToolName,
                [array]$ToolSchemas
            )

            $ToolName -in (Get-StubAvailableToolNames -ToolSchemas $ToolSchemas)
        }

        function Get-StubUrlFromPrompt {
            param([string]$Prompt)

            $match = [regex]::Match($Prompt, 'https?://\S+')
            if ($match.Success) {
                return $match.Value.TrimEnd('.', ',', ';', ')', ']', '>')
            }

            return $null
        }

        function New-StubToolCall {
            param(
                [string]$ToolName,
                [hashtable]$ToolInput
            )

            [PSCustomObject]@{
                Type      = 'tool_call'
                ToolName  = $ToolName
                ToolInput = $ToolInput
                ToolUseId = "stub_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            }
        }

        function Get-StubPlanState {
            param([array]$Messages)

            $toolUses = @()
            $planPreviewMode = $false

            foreach ($message in $Messages) {
                if ($message.role -eq 'assistant' -and $message.content[0].type -eq 'tool_use') {
                    $toolUses += $message.content[0]
                }

                if (
                    $message.role -eq 'user' -and
                    $message.content[0].type -eq 'tool_result' -and
                    "$($message.content[0].content)" -match '^Plan preview only:'
                ) {
                    $planPreviewMode = $true
                }
            }

            [PSCustomObject]@{
                ToolUses        = $toolUses
                PlanPreviewMode = $planPreviewMode
            }
        }

        function Get-StubPlanSequence {
            param(
                [string]$Prompt,
                [array]$ToolSchemas
            )

            $normalizedPrompt = if ($Prompt) { $Prompt.ToLowerInvariant() } else { '' }
            $url = Get-StubUrlFromPrompt -Prompt $Prompt
            $steps = [System.Collections.Generic.List[object]]::new()

            if ($url -and (Test-StubToolAvailable -ToolName 'Fetch-WebPage' -ToolSchemas $ToolSchemas)) {
                $steps.Add((New-StubToolCall -ToolName 'Fetch-WebPage' -ToolInput @{
                    Url = $url
                })) | Out-Null

                return [PSCustomObject]@{
                    Steps       = @($steps)
                    PlanSummary = 'Fetch the page text first, then summarize the key points from the webpage content.'
                }
            }

            if (
                ($normalizedPrompt -match '\bhealth\b' -or
                 $normalizedPrompt -match '\bcpu\b' -or
                 $normalizedPrompt -match '\bram\b' -or
                 $normalizedPrompt -match '\bmemory\b' -or
                 $normalizedPrompt -match '\bhard drive\b' -or
                 $normalizedPrompt -match '\bdisk\b' -or
                 $normalizedPrompt -match '\bstorage\b' -or
                 $normalizedPrompt -match '\bdrive space\b' -or
                 $normalizedPrompt -match '\breboot\b' -or
                 $normalizedPrompt -match '\buptime\b')
            ) {
                if (Test-StubToolAvailable -ToolName 'Get-SystemTriage' -ToolSchemas $ToolSchemas) {
                    $steps.Add((New-StubToolCall -ToolName 'Get-SystemTriage' -ToolInput @{})) | Out-Null
                } elseif (Test-StubToolAvailable -ToolName 'Get-SystemSummary' -ToolSchemas $ToolSchemas) {
                    $steps.Add((New-StubToolCall -ToolName 'Get-SystemSummary' -ToolInput @{
                        View = 'Full'
                    })) | Out-Null
                }

                if (Test-StubToolAvailable -ToolName 'Get-StorageStatus' -ToolSchemas $ToolSchemas) {
                    $steps.Add((New-StubToolCall -ToolName 'Get-StorageStatus' -ToolInput @{
                        View = 'Summary'
                    })) | Out-Null
                }

                if (Test-StubToolAvailable -ToolName 'Get-NetworkStatus' -ToolSchemas $ToolSchemas) {
                    $steps.Add((New-StubToolCall -ToolName 'Get-NetworkStatus' -ToolInput @{})) | Out-Null
                }

                return [PSCustomObject]@{
                    Steps       = @($steps)
                    PlanSummary = 'Start with deterministic system triage, add storage and network context only if needed, then summarize overall status and the most important issues.'
                }
            }

            if (
                ($normalizedPrompt -match '\bbiggest\b' -or
                 $normalizedPrompt -match '\blargest\b' -or
                 $normalizedPrompt -match '\bdownload' -or
                 $normalizedPrompt -match '\bcleanup\b' -or
                 $normalizedPrompt -match '\bclean up\b')
            ) {
                if (Test-StubToolAvailable -ToolName 'Get-CleanupSummary' -ToolSchemas $ToolSchemas) {
                    $steps.Add((New-StubToolCall -ToolName 'Get-CleanupSummary' -ToolInput @{
                        Scope = "$env:USERPROFILE\Downloads"
                        Limit = 10
                        MinSizeMB = 50
                    })) | Out-Null
                } elseif (Test-StubToolAvailable -ToolName 'Search-Files' -ToolSchemas $ToolSchemas) {
                    $steps.Add((New-StubToolCall -ToolName 'Search-Files' -ToolInput @{
                        Scope     = "$env:USERPROFILE\Downloads"
                        Limit     = 10
                        SortBy    = 'Size'
                        Aggregate = $false
                    })) | Out-Null
                }

                if (Test-StubToolAvailable -ToolName 'Get-DirectoryListing' -ToolSchemas $ToolSchemas) {
                    $steps.Add((New-StubToolCall -ToolName 'Get-DirectoryListing' -ToolInput @{
                        Path  = "$env:USERPROFILE\Downloads"
                        Limit = 25
                    })) | Out-Null
                }

                return [PSCustomObject]@{
                    Steps       = @($steps)
                    PlanSummary = 'Start with a deterministic cleanup summary, then inspect directory context only if the ranked candidates still look ambiguous.'
                }
            }

            if (
                ($normalizedPrompt -match '\bread\b' -or
                 $normalizedPrompt -match '\bconfig\b' -or
                 $normalizedPrompt -match '\blog\b' -or
                 $normalizedPrompt -match '\bmanifest\b' -or
                 $normalizedPrompt -match '\breadme\b') -and
                (Test-StubToolAvailable -ToolName 'Read-FileContent' -ToolSchemas $ToolSchemas)
            ) {
                $path = if ($normalizedPrompt -match 'tools-manifest\.json') {
                    'tools-manifest.json'
                }
                elseif ($normalizedPrompt -match 'config\.json') {
                    'config.json'
                }
                elseif ($normalizedPrompt -match 'readme') {
                    'README.md'
                }
                elseif ($normalizedPrompt -match '\blog\b') {
                    'powerclaw.log'
                }
                else {
                    'README.md'
                }

                $steps.Add((New-StubToolCall -ToolName 'Read-FileContent' -ToolInput @{
                    Path = $path
                })) | Out-Null

                return [PSCustomObject]@{
                    Steps       = @($steps)
                    PlanSummary = 'Read the file first, then explain the settings, warnings, or important details in plain English.'
                }
            }

            if (
                ($normalizedPrompt -match '\bdownloads\b' -or
                 $normalizedPrompt -match '\blist\b' -or
                 $normalizedPrompt -match '\bcontents\b') -and
                (Test-StubToolAvailable -ToolName 'Get-DirectoryListing' -ToolSchemas $ToolSchemas)
            ) {
                $steps.Add((New-StubToolCall -ToolName 'Get-DirectoryListing' -ToolInput @{
                    Path  = "$env:USERPROFILE\Downloads"
                    Limit = 25
                })) | Out-Null

                return [PSCustomObject]@{
                    Steps       = @($steps)
                    PlanSummary = 'Inspect the directory contents first, then summarize what stands out.'
                }
            }

            if (Test-StubToolAvailable -ToolName 'Get-TopProcesses' -ToolSchemas $ToolSchemas) {
                $steps.Add((New-StubToolCall -ToolName 'Get-TopProcesses' -ToolInput @{
                    SortBy = if ($normalizedPrompt -match '\bmemory\b' -or $normalizedPrompt -match '\bram\b') { 'Memory' } else { 'CPU' }
                    Count  = 5
                })) | Out-Null

                return [PSCustomObject]@{
                    Steps       = @($steps)
                    PlanSummary = 'Check the top processes first, then explain the main resource consumer.'
                }
            }

            return [PSCustomObject]@{
                Steps       = @()
                PlanSummary = "[Stub] No suitable approved tool was available for this demo request."
            }
        }

        function Get-StubToolPlan {
            param(
                [string]$Prompt,
                [array]$ToolSchemas,
                [array]$Messages
            )

            $planSequence = Get-StubPlanSequence -Prompt $Prompt -ToolSchemas $ToolSchemas
            $planState = Get-StubPlanState -Messages $Messages

            if ($planState.PlanPreviewMode) {
                $nextIndex = @($planState.ToolUses).Count
                if ($nextIndex -lt @($planSequence.Steps).Count) {
                    return $planSequence.Steps[$nextIndex]
                }

                return [PSCustomObject]@{
                    Type    = 'final_answer'
                    Content = $planSequence.PlanSummary
                }
            }

            if (@($planSequence.Steps).Count -gt 0) {
                return $planSequence.Steps[0]
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = $planSequence.PlanSummary
            }
        }

        function Get-StubFinalAnswer {
            param(
                [string]$Prompt,
                [array]$Messages
            )

            $toolUse = $null
            $toolResult = $null
            for ($i = $Messages.Count - 1; $i -ge 0; $i--) {
                $message = $Messages[$i]
                if (-not $toolResult -and $message.role -eq 'user' -and $message.content[0].type -eq 'tool_result') {
                    $toolResult = [string]$message.content[0].content
                    continue
                }
                if (-not $toolUse -and $message.role -eq 'assistant' -and $message.content[0].type -eq 'tool_use') {
                    $toolUse = $message.content[0]
                }
                if ($toolUse -and $toolResult) {
                    break
                }
            }

            $toolName = if ($toolUse) { [string]$toolUse.name } else { 'the selected tool' }
            $normalizedPrompt = if ($Prompt) { $Prompt.ToLowerInvariant() } else { '' }
            $lines = @($toolResult -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $previewLines = @($lines | Select-Object -First 3)
            $preview = if ($previewLines.Count -gt 0) { $previewLines -join '; ' } else { 'No output was returned.' }

            switch ($toolName) {
                'Get-CleanupSummary' {
                    return @"
[Stub] Demo answer from ${toolName}:
What I found: the cleanup summary already ranks the most relevant cleanup candidates for the bounded scope.
What looks worth reviewing: start with the highest-ranked execution-allowed remnants, then move to review-only categories.
Candidate states: separate review-only files from execution-allowed-after-confirmation remnants before any delete action.
Next safe action: preview the named candidates and confirm only the items the user explicitly wants removed.
Preview: $preview
"@
                }
                'Get-SystemTriage' {
                    return @"
[Stub] Demo answer from ${toolName}:
Overall status: the triage already summarizes the machine state into a bounded operator readout.
Key findings: call out the highest-severity findings first, then the recommended next checks.
Implication: use narrower tools only if the triage points to something ambiguous or worth confirming.
Preview: $preview
"@
                }
                'Get-SystemSummary' {
                    $cpuMatch = [regex]::Match($toolResult, 'CPULoadPct\s*[: ]+\s*([0-9.]+)')
                    $ramMatch = [regex]::Match($toolResult, 'RAMUsedPct\s*[: ]+\s*([0-9.]+)')
                    $uptimeMatch = [regex]::Match($toolResult, 'Uptime\s*[: ]+\s*(.+)')
                    $cpuText = if ($cpuMatch.Success) { "$($cpuMatch.Groups[1].Value)% CPU load" } else { 'current CPU load available in the summary' }
                    $ramText = if ($ramMatch.Success) { "$($ramMatch.Groups[1].Value)% RAM in use" } else { 'RAM usage included in the summary' }
                    $uptimeText = if ($uptimeMatch.Success) { "uptime $($uptimeMatch.Groups[1].Value.Trim())" } else { 'uptime included in the summary' }
                    return @"
[Stub] Demo answer from ${toolName}:
Overall status: the machine looks broadly healthy.
Key findings: $cpuText; $ramText; $uptimeText.
Next checks: investigate only if one of those signals looks abnormal for the current workload.
"@
                }
                'Search-Files' {
                    return @"
[Stub] Demo answer from ${toolName}:
What I found: several large files worth review in Downloads.
What looks worth reviewing: the biggest items first, based on size and recency.
What likely looks intentional: large installers, backups, or media may still be there on purpose.
What is ambiguous: size alone is not enough to call something safe to delete.
Next safe action: preview the specific files and confirm before deletion.
Preview: $preview
"@
                }
                'Read-FileContent' {
                    return @"
[Stub] Demo answer from ${toolName}:
Answer: this file contains the main settings or content relevant to the request.
Evidence: PowerClaw would pull out the specific settings, warnings, or notable lines that matter.
Implication: explain what these values mean for the current setup or workflow, then call out the next action only if the file suggests one.
Preview: $preview
"@
                }
                'Fetch-WebPage' {
                    return @"
[Stub] Demo answer from ${toolName}:
Answer: PowerClaw would summarize the page contents directly from fetched page text.
Evidence: call out the important topics, releases, or claims on the page.
Implication: mention why those takeaways matter for the user's question instead of repeating the page section-by-section.
Preview: $preview
"@
                }
                'Get-DirectoryListing' {
                    return @"
[Stub] Demo answer from ${toolName}:
What I found: PowerClaw would turn the directory listing into a readable summary instead of a raw dump.
What looks worth reviewing: call out the entries that stand out by size, recency, or type.
What is ambiguous or likely intentional: separate obvious review targets from files that may belong to the current workflow.
Next safe action: inspect the most relevant files before taking action.
Preview: $preview
"@
                }
                'Get-TopProcesses' {
                    $firstDataLine = $lines | Where-Object { $_ -match '^\S+\s+\d+\s+' } | Select-Object -First 1
                    if (-not $firstDataLine) {
                        $firstDataLine = $preview
                    }
                    $focus = if ($normalizedPrompt -match '\bmemory\b' -or $normalizedPrompt -match '\bram\b') { 'memory' } else { 'CPU' }
                    return @"
[Stub] Demo answer from ${toolName}:
Overall status: resource usage is concentrated in a small number of processes.
Key finding: the main $focus consumer is highlighted first.
Implication: explain whether that process looks expected for the current workload.
Preview: $firstDataLine
"@
                }
                default {
                    return "[Stub] Demo answer from ${toolName}: PowerClaw would answer from the tool output rather than asking the model to invent shell steps. Output preview: $preview"
                }
            }
        }

        $initialPrompt = if ($Messages.Count -gt 0) { [string]$Messages[0].content } else { '' }
        $stubPlanState = Get-StubPlanState -Messages $Messages
        $isFollowUp = $Messages.Count -gt 2
        if ($isFollowUp -and -not $stubPlanState.PlanPreviewMode) {
            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = Get-StubFinalAnswer -Prompt $initialPrompt -Messages $Messages
            }
        }

        return Get-StubToolPlan -Prompt $initialPrompt -ToolSchemas $ToolSchemas -Messages $Messages
    }

    $config = Get-Content (Join-Path $PSScriptRoot '..\config.json') -Raw | ConvertFrom-Json

    switch ($config.provider) {
        "claude" { return Send-ClaudeRequest -SystemPrompt $SystemPrompt -Messages $Messages -ToolSchemas $ToolSchemas -Config $config }
        "openai" { return Send-OpenAiRequest -SystemPrompt $SystemPrompt -Messages $Messages -ToolSchemas $ToolSchemas -Config $config }
        default  { throw "Unknown provider '$($config.provider)'. Supported values in config.json are 'claude' or 'openai'." }
    }
}
