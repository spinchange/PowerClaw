# core/Invoke-ClawLoop.ps1

function Write-ClawLoopLogEntry {
    param(
        [string]$LogPath,
        [hashtable]$Entry
    )

    if (-not $LogPath) {
        return
    }

    $allowedEventOutcomes = @{
        step_start       = @('started')
        model_response   = @('received')
        plan_preview     = @('previewed')
        final_answer     = @('final_answer')
        tool_requested   = @('requested')
        tool_unavailable = @('rejected')
        tool_rejected    = @('rejected')
        tool_skipped     = @('blocked', 'declined', 'dry_run')
        tool_confirmed   = @('confirmed')
        tool_result      = @('success', 'error', 'executed_success', 'executed_error')
        loop_abort       = @('aborted')
    }

    if (-not $Entry.ContainsKey('Event') -or -not $Entry.ContainsKey('Outcome') -or -not $Entry.ContainsKey('Step')) {
        return
    }

    $eventName = [string]$Entry.Event
    $outcome = [string]$Entry.Outcome
    if (-not $allowedEventOutcomes.ContainsKey($eventName)) {
        return
    }

    if ($allowedEventOutcomes[$eventName] -notcontains $outcome) {
        return
    }

    $safeEntry = @{}
    foreach ($key in $Entry.Keys) {
        $value = $Entry[$key]
        if ($null -eq $value) {
            continue
        }

        if ($value -is [string] -or $value -is [ValueType] -or $value -is [bool]) {
            $safeEntry[$key] = $value
            continue
        }

        $safeEntry[$key] = $value
    }

    $safeEntry.SchemaVersion = '1'
    $safeEntry.Kind = 'loop_log'
    $safeEntry.Timestamp = Get-Date -Format 'o'
    $schemaPath = Join-Path $PSScriptRoot '..\docs\loop-log-v1.schema.json'
    $json = $safeEntry | ConvertTo-Json -Depth 10 -Compress

    try {
        if (-not (Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop)) {
            return
        }
    }
    catch {
        return
    }

    Add-Content -Path $LogPath -Value $json -ErrorAction SilentlyContinue
}

function Get-ClawWritePolicyReason {
    param(
        [string]$Reason
    )

    switch ($Reason) {
        'write_policy_blocked' { return 'explicit_write_intent_required' }
        'write_targets_not_previously_enumerated' { return 'prior_evidence_required' }
        'permanent_delete_intent_not_explicit' { return 'explicit_permanent_intent_required' }
        'delete_target_reference_not_specific_enough' { return 'specific_user_reference_required' }
        'confirmation_declined' { return 'confirmation_declined' }
        'dry_run' { return 'execution_mode_dry_run' }
        default { return $null }
    }
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

function Test-ClawExplicitPermanentDeleteIntent {
    param(
        [string]$UserGoal
    )

    if ([string]::IsNullOrWhiteSpace($UserGoal)) {
        return $false
    }

    return (
        $UserGoal -match '\bpermanent(?:ly)?\b' -or
        $UserGoal -match '\bdelete permanently\b' -or
        $UserGoal -match '\bpermanently delete\b' -or
        $UserGoal -match '\berase forever\b' -or
        $UserGoal -match '\bnot (?:to|into) recycle\b' -or
        $UserGoal -match '\bbypass (?:the )?recycle bin\b'
    )
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
        $UserGoal -match "\bwhat'?s going on with my (?:system|computer|machine)\b" -or
        $UserGoal -match '\bwhat is going on with my (?:system|computer|machine)\b' -or
        $UserGoal -match '\bhow is my (?:system|computer|machine)\b' -or
        $UserGoal -match "\bwhat'?s eating my cpu\b" -or
        $UserGoal -match '\bhard drive\b' -or
        $UserGoal -match '\bdisk\b' -or
        $UserGoal -match '\bstorage\b' -or
        $UserGoal -match '\bdrive space\b' -or
        $UserGoal -match '\bcpu\b' -or
        $UserGoal -match '\bmemory\b' -or
        $UserGoal -match '\bram\b'
    )
}

function Test-ClawRecentChangesGoal {
    param(
        [string]$UserGoal
    )

    if ([string]::IsNullOrWhiteSpace($UserGoal)) {
        return $false
    }

    return (
        $UserGoal -match '\bwhat changed\b' -or
        $UserGoal -match '\brecent changes\b' -or
        $UserGoal -match '\bchanged recently\b' -or
        $UserGoal -match '\brecently changed\b' -or
        $UserGoal -match '\blast \d+ (?:hour|hours|day|days)\b' -or
        $UserGoal -match '\bin the last \d+ (?:hour|hours|day|days)\b'
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
        $UserGoal -match '\bfiles?\s+(?:that|i|we)?\s*(?:can|could|should)?\s*delete\b' -or
        $UserGoal -match '\bidentify\s+files?\s+that\s+i\s+can\s+delete\b' -or
        $UserGoal -match '\bwhat\s+files?\s+can\s+i\s+delete\b' -or
        $UserGoal -match '\bfiles?\s+to\s+delete\b' -or
        $UserGoal -match '\bsafe\s+to\s+delete\b' -or
        $UserGoal -match '\bwhat should i clean\b' -or
        $UserGoal -match '\bwhat looks safe to remove\b' -or
        $UserGoal -match '\bwhat can i delete\b'
    )
}

function Test-ClawInvestigationGoal {
    param(
        [string]$UserGoal
    )

    if ([string]::IsNullOrWhiteSpace($UserGoal)) {
        return $false
    }

    return (
        $UserGoal -match '\bread\b' -or
        $UserGoal -match '\bconfig\b' -or
        $UserGoal -match '\blog\b' -or
        $UserGoal -match '\bmanifest\b' -or
        $UserGoal -match '\breadme\b' -or
        $UserGoal -match 'https?://'
    )
}

function Test-ClawBroadCleanupDiscoveryTool {
    param(
        [string]$ToolName
    )

    $ToolName -in @('Search-Files', 'Get-StorageStatus', 'Get-DirectoryListing')
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

function Get-ClawDeleteTargetPolicy {
    param(
        [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension(($Path ?? '')).ToLowerInvariant()

    if ($extension -in @('.log', '.tmp', '.bak', '.old', '.dmp')) {
        return 'low_risk'
    }

    if ($extension -in @(
            '.exe', '.msi', '.msix', '.msu', '.iso',
            '.zip', '.7z', '.rar', '.tar', '.gz', '.bz2',
            '.mp3', '.wav', '.flac', '.mp4', '.mkv', '.avi', '.mov',
            '.jpg', '.jpeg', '.png', '.webp',
            '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
            '.ps1', '.psm1', '.psd1', '.json', '.config', '.xml', '.yml', '.yaml', '.md', '.txt', '.csv'
        )) {
        return 'requires_specific_reference'
    }

    return 'default'
}

function Test-ClawGoalReferencesDeleteTargetsSpecifically {
    param(
        [string]$UserGoal,
        [hashtable]$ToolInput
    )

    if ([string]::IsNullOrWhiteSpace($UserGoal) -or -not $ToolInput -or -not $ToolInput.ContainsKey('Paths')) {
        return $false
    }

    $normalizedGoal = $UserGoal.ToLowerInvariant()
    foreach ($path in @($ToolInput.Paths)) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $fullPath = [string]$path
        $leaf = [System.IO.Path]::GetFileName($fullPath)
        $extension = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)

        if ($normalizedGoal -match [regex]::Escape($fullPath.ToLowerInvariant())) {
            return $true
        }
        if (-not [string]::IsNullOrWhiteSpace($leaf) -and $normalizedGoal -match [regex]::Escape($leaf.ToLowerInvariant())) {
            return $true
        }
        if (-not [string]::IsNullOrWhiteSpace($stem) -and $stem.Length -ge 4 -and $normalizedGoal -match [regex]::Escape($stem.ToLowerInvariant())) {
            return $true
        }
        if (-not [string]::IsNullOrWhiteSpace($extension) -and $normalizedGoal -match [regex]::Escape($extension)) {
            return $true
        }
    }

    return $false
}

function Test-ClawDeleteTargetsNeedSpecificReference {
    param(
        [hashtable]$ToolInput
    )

    if (-not $ToolInput -or -not $ToolInput.ContainsKey('Paths')) {
        return $false
    }

    foreach ($path in @($ToolInput.Paths)) {
        if ((Get-ClawDeleteTargetPolicy -Path ([string]$path)) -eq 'requires_specific_reference') {
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

function Format-ClawPolicyToolResultContent {
    param(
        [string]$PolicyReason,
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($PolicyReason)) {
        return $Message
    }

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return "PolicyReason: $PolicyReason"
    }

    return "PolicyReason: $PolicyReason`n$Message"
}

function Format-ClawControlToolResultContent {
    param(
        [string]$ControlReason,
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($ControlReason)) {
        return $Message
    }

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return "ControlReason: $ControlReason"
    }

    return "ControlReason: $ControlReason`n$Message"
}

function Test-ClawSyntheticToolResultContent {
    param(
        [string]$Content
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $true
    }

    return (
        $Content -match '^PolicyReason: ' -or
        $Content -match '^ControlReason: ' -or
        $Content -match '^Plan preview only:' -or
        $Content -match '^Error: repeated tool call detected' -or
        $Content -match '^Error: tool .+ is not available in the approved registry' -or
        $Content -match '^Health-check latency budget reached:' -or
        $Content -match '^Cleanup discovery budget reached:' -or
        $Content -match '^Cleanup latency budget reached:' -or
        $Content -match '^Investigation latency budget reached:' -or
        $Content -match '^Blocked by write policy:' -or
        $Content -match '^User declined to run ' -or
        $Content -match '^\(dry run'
    )
}

function Test-ClawSyntheticFinalAnswerContent {
    param(
        [string]$Content
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $true
    }

    return (
        $Content -match '^handled\b' -or
        $Content -match '^done$' -or
        $Content -match '^stubbed final answer$' -or
        $Content -match '^cleanup summary from\b' -or
        $Content -match '^investigation summary from\b' -or
        $Content -match '^health summary from\b' -or
        $Content -match '^recent changes summary from\b'
    )
}

function Get-ClawLatestToolEvidence {
    param(
        [array]$Messages
    )

    $toolName = $null
    $toolResult = $null

    for ($i = $Messages.Count - 1; $i -ge 0; $i--) {
        $message = $Messages[$i]
        if (
            -not $toolResult -and
            $message.role -eq 'user' -and
            $message.content -is [array] -and
            $message.content[0].type -eq 'tool_result' -and
            -not (Test-ClawSyntheticToolResultContent -Content ([string]$message.content[0].content))
        ) {
            $toolResult = [string]$message.content[0].content
            continue
        }

        if (
            -not $toolName -and
            $message.role -eq 'assistant' -and
            $message.content -is [array] -and
            $message.content[0].type -eq 'tool_use'
        ) {
            $toolName = [string]$message.content[0].name
        }

        if ($toolName -and $toolResult) {
            break
        }
    }

    if (-not $toolName -and -not $toolResult) {
        return $null
    }

    $previewLines = @(
        @($toolResult -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) |
        Select-Object -First 6
    )

    return [PSCustomObject]@{
        ToolName = $toolName
        ToolResult = $toolResult
        Preview = if ($previewLines.Count -gt 0) { $previewLines -join '; ' } else { '' }
    }
}

function Get-ClawStructuredEvidencePreview {
    param(
        [string]$ToolName,
        [string]$ToolResult
    )

    if ([string]::IsNullOrWhiteSpace($ToolResult)) {
        return ''
    }

    $lines = @($ToolResult -split "`r?`n")

    switch ($ToolName) {
        'Search-Files' {
            $dataLines = @($lines | Where-Object { $_ -match '^[^\s].+\s+[A-Za-z]:\\' } | Select-Object -First 3)
            if ($dataLines.Count -gt 0) {
                return ($dataLines -join '; ')
            }
        }
        'Search-LocalKnowledge' {
            $dataLines = @($lines | Where-Object { $_ -match '^[^\s].+\s+[A-Za-z]:\\' } | Select-Object -First 3)
            if ($dataLines.Count -gt 0) {
                return ($dataLines -join '; ')
            }
        }
        'Get-DirectoryListing' {
            $dataLines = @($lines | Where-Object { $_ -match '^[^\s].+\s+\d{4}-\d{2}-\d{2}' -or $_ -match '^[^\s].+\s+(True|False)$' } | Select-Object -First 3)
            if ($dataLines.Count -gt 0) {
                return ($dataLines -join '; ')
            }
        }
        'Read-FileContent' {
            $contentIndex = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s*Content\s*:\s*(.*)$') {
                    $contentIndex = $i
                    break
                }
            }

            if ($contentIndex -ge 0) {
                $contentLines = [System.Collections.Generic.List[string]]::new()
                $firstContent = $Matches[1]
                if (-not [string]::IsNullOrWhiteSpace($firstContent)) {
                    $contentLines.Add($firstContent.Trim()) | Out-Null
                }

                for ($j = $contentIndex + 1; $j -lt $lines.Count; $j++) {
                    if ($lines[$j] -match '^\s{2,}\S') {
                        $contentLines.Add($lines[$j].Trim()) | Out-Null
                        if ($contentLines.Count -ge 4) {
                            break
                        }
                        continue
                    }
                    break
                }

                if ($contentLines.Count -gt 0) {
                    return ($contentLines -join '; ')
                }
            }
        }
        'Fetch-WebPage' {
            $titleLine = @($lines | Where-Object { $_ -match '^\s*Title\s*:' } | Select-Object -First 1)
            $contentIndex = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s*Content\s*:\s*(.*)$') {
                    $contentIndex = $i
                    break
                }
            }

            $parts = [System.Collections.Generic.List[string]]::new()
            if ($titleLine) {
                $parts.Add($titleLine[0].Trim()) | Out-Null
            }
            if ($contentIndex -ge 0) {
                $contentText = $Matches[1].Trim()
                if (-not [string]::IsNullOrWhiteSpace($contentText)) {
                    $parts.Add($contentText) | Out-Null
                }
            }

            if ($parts.Count -gt 0) {
                return ($parts -join '; ')
            }
        }
        'Get-RecentChangesSummary' {
            $summaryLine = @($lines | Where-Object { $_ -match '^\s*summary\s*:\s*@\{.*headline=' } | Select-Object -First 1)
            $filesLine = @($lines | Where-Object { $_ -match '^\s*recent_files\s*:' } | Select-Object -First 1)
            $sourcesLine = @($lines | Where-Object { $_ -match '^\s*recent_event_sources\s*:' } | Select-Object -First 1)

            $parts = [System.Collections.Generic.List[string]]::new()
            if ($summaryLine) {
                $parts.Add($summaryLine[0].Trim()) | Out-Null
            }
            if ($filesLine) {
                $parts.Add($filesLine[0].Trim()) | Out-Null
            }
            if ($sourcesLine) {
                $parts.Add($sourcesLine[0].Trim()) | Out-Null
            }

            if ($parts.Count -gt 0) {
                return ($parts -join '; ')
            }
        }
    }

    $fallbackLines = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 6)
    if ($fallbackLines.Count -gt 0) {
        return ($fallbackLines -join '; ')
    }

    return ''
}

function Get-ClawCleanupEvidenceGuidance {
    param(
        [string]$ToolName,
        [string]$ToolResult
    )

    if ([string]::IsNullOrWhiteSpace($ToolResult)) {
        return 'Large installers, media, backups, or project artifacts may still be intentional, so size alone is not enough to call them safe to delete.'
    }

    $lines = @($ToolResult -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $installerHits = 0
    $archiveHits = 0
    $mediaHits = 0
    $logHits = 0
    $folderHits = 0

    foreach ($line in $lines) {
        $normalizedLine = $line.ToLowerInvariant()

        if ($normalizedLine -match '\.(exe|msi|msix|msu|iso)\b') {
            $installerHits++
        }
        if ($normalizedLine -match '\.(zip|7z|rar|tar|gz|bz2)\b') {
            $archiveHits++
        }
        if ($normalizedLine -match '\.(mp3|wav|flac|mp4|mkv|avi|mov|jpg|jpeg|png|webp)\b') {
            $mediaHits++
        }
        if ($normalizedLine -match '\.(log|tmp|bak|old|dmp)\b') {
            $logHits++
        }
        if ($ToolName -eq 'Get-DirectoryListing' -and $normalizedLine -match '\btrue$') {
            $folderHits++
        }
    }

    $parts = [System.Collections.Generic.List[string]]::new()

    if ($installerHits -gt 0) {
        $parts.Add('Installer images or setup packages can be disposable if they were only kept for one-time setup, but keep them if they are part of your normal reinstall path.') | Out-Null
    }
    if ($archiveHits -gt 0) {
        $parts.Add('Archives may be backups or bundled deliverables, so confirm they are duplicated elsewhere before deleting them.') | Out-Null
    }
    if ($mediaHits -gt 0) {
        $parts.Add('Large media files are often intentional recordings or downloads, so review recency and purpose before treating them as cleanup candidates.') | Out-Null
    }
    if ($logHits -gt 0) {
        $parts.Add('Logs, temp files, dumps, or backup-style remnants are usually stronger cleanup candidates, but confirm they are not still needed for troubleshooting.') | Out-Null
    }
    if ($folderHits -gt 0) {
        $parts.Add('Folders need an extra check because deleting them can remove multiple nested files, not just one surfaced item.') | Out-Null
    }

    if ($parts.Count -eq 0) {
        return 'Large installers, media, backups, or project artifacts may still be intentional, so size alone is not enough to call them safe to delete.'
    }

    return ($parts -join ' ')
}

function Get-ClawCleanupReviewRanking {
    param(
        [string]$ToolName,
        [string]$ToolResult
    )

    if ([string]::IsNullOrWhiteSpace($ToolResult)) {
        return 'Start with the most obviously disposable surfaced files first, then review anything that may be intentional before deleting it.'
    }

    $lines = @($ToolResult -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $categoryCounts = [ordered]@{
        logs       = 0
        installers = 0
        archives   = 0
        media      = 0
        folders    = 0
    }

    foreach ($line in $lines) {
        $normalizedLine = $line.ToLowerInvariant()

        if ($normalizedLine -match '\.(log|tmp|bak|old|dmp)\b') {
            $categoryCounts.logs++
        }
        if ($normalizedLine -match '\.(exe|msi|msix|msu|iso)\b') {
            $categoryCounts.installers++
        }
        if ($normalizedLine -match '\.(zip|7z|rar|tar|gz|bz2)\b') {
            $categoryCounts.archives++
        }
        if ($normalizedLine -match '\.(mp3|wav|flac|mp4|mkv|avi|mov|jpg|jpeg|png|webp)\b') {
            $categoryCounts.media++
        }
        if ($ToolName -eq 'Get-DirectoryListing' -and $normalizedLine -match '\btrue$') {
            $categoryCounts.folders++
        }
    }

    $ranked = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $categoryCounts.GetEnumerator()) {
        if ([int]$entry.Value -gt 0) {
            $ranked.Add([string]$entry.Key) | Out-Null
        }
    }

    if ($ranked.Count -eq 0) {
        return 'Start with the most obviously disposable surfaced files first, then review anything that may be intentional before deleting it.'
    }

    $labels = foreach ($category in $ranked) {
        switch ($category) {
            'logs' { 'logs, temp files, and dump-style remnants' }
            'installers' { 'one-time installers or setup images' }
            'archives' { 'archives and bundled backups' }
            'media' { 'large media files' }
            'folders' { 'folders last, because they can remove multiple nested items at once' }
        }
    }

    return "Review order: $($labels -join ', then ')."
}

function Get-ClawCleanupCandidateStates {
    param(
        [string]$ToolName,
        [string]$ToolResult
    )

    if ([string]::IsNullOrWhiteSpace($ToolResult)) {
        return 'review-only by default until the surfaced files are classified more clearly.'
    }

    $lines = @($ToolResult -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $hasLogs = $false
    $hasInstallers = $false
    $hasArchives = $false
    $hasMedia = $false
    $hasFolders = $false
    $hasOther = $false

    foreach ($line in $lines) {
        $normalizedLine = $line.ToLowerInvariant()
        $matched = $false

        if ($normalizedLine -match '\.(log|tmp|bak|old|dmp)\b') {
            $hasLogs = $true
            $matched = $true
        }
        if ($normalizedLine -match '\.(exe|msi|msix|msu|iso)\b') {
            $hasInstallers = $true
            $matched = $true
        }
        if ($normalizedLine -match '\.(zip|7z|rar|tar|gz|bz2)\b') {
            $hasArchives = $true
            $matched = $true
        }
        if ($normalizedLine -match '\.(mp3|wav|flac|mp4|mkv|avi|mov|jpg|jpeg|png|webp)\b') {
            $hasMedia = $true
            $matched = $true
        }
        if ($ToolName -eq 'Get-DirectoryListing' -and $normalizedLine -match '\btrue$') {
            $hasFolders = $true
            $matched = $true
        }

        if (-not $matched -and $normalizedLine -notmatch '^(name|path|sizemb|datemodified|length|lastwritetime|psiscontainer)\b') {
            $hasOther = $true
        }
    }

    $allowed = [System.Collections.Generic.List[string]]::new()
    $reviewOnly = [System.Collections.Generic.List[string]]::new()

    if ($hasLogs) {
        $allowed.Add('execution-allowed after confirmation: logs, temp files, dumps, and backup-style remnants that were already enumerated') | Out-Null
    }
    if ($hasInstallers) {
        $reviewOnly.Add('review-only: installers and setup images unless the user names them specifically') | Out-Null
    }
    if ($hasArchives) {
        $reviewOnly.Add('review-only: archives and backup bundles unless the user confirms they are redundant') | Out-Null
    }
    if ($hasMedia) {
        $reviewOnly.Add('review-only: media files unless the user clearly identifies the exact recording or download') | Out-Null
    }
    if ($hasFolders) {
        $reviewOnly.Add('review-only: folders because they can remove nested contents, not just one surfaced item') | Out-Null
    }
    if ($hasOther) {
        $reviewOnly.Add('review-only: uncategorized files until the user names the exact file or type to remove') | Out-Null
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    if ($allowed.Count -gt 0) {
        $parts.Add(($allowed -join '; ')) | Out-Null
    }
    if ($reviewOnly.Count -gt 0) {
        $parts.Add(($reviewOnly -join '; ')) | Out-Null
    }

    if ($parts.Count -eq 0) {
        return 'review-only by default until the surfaced files are classified more clearly.'
    }

    return ($parts -join '; ')
}

function Format-ClawFinalAnswer {
    param(
        [string]$Content,
        [array]$Messages,
        [bool]$IsHealthCheckGoal,
        [bool]$IsCleanupGoal,
        [bool]$IsInvestigationGoal,
        [bool]$IsRecentChangesGoal
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $Content
    }

    $trimmedContent = $Content.Trim()
    $hasStructuredHealthSections = $trimmedContent -match '(?im)^(overall status|key findings|why it matters|next checks)\s*:'
    $hasStructuredCleanupSections = $trimmedContent -match '(?im)^(what i found|what looks worth reviewing|what likely looks intentional|what is ambiguous|what is ambiguous or risky|next safe action)\s*:'
    $hasStructuredInvestigationSections = $trimmedContent -match '(?im)^(answer|summary|evidence|implication|key details|key takeaways)\s*:'
    $hasStructuredRecentChangesSections = $trimmedContent -match '(?im)^(what changed|what stands out|implication|next checks)\s*:'

    if (Test-ClawSyntheticFinalAnswerContent -Content $trimmedContent) {
        return $Content
    }

    if ($IsHealthCheckGoal -and -not $hasStructuredHealthSections) {
        $evidence = Get-ClawLatestToolEvidence -Messages $Messages
        if (-not $evidence) {
            return $Content
        }
        $evidencePreview = Get-ClawStructuredEvidencePreview -ToolName $evidence.ToolName -ToolResult $evidence.ToolResult
        if ([string]::IsNullOrWhiteSpace($evidencePreview)) {
            $evidencePreview = 'Use the health signals already gathered from the read-only tools.'
        }
        return @"
Overall status: $trimmedContent
Key findings: $evidencePreview
Why it matters: Interpret whether the surfaced signals look healthy, degraded, or worth attention based on the current evidence rather than repeating raw metrics.
Next checks: Only inspect narrower tools if the current evidence still looks abnormal or ambiguous.
"@.Trim()
    }

    if ($IsCleanupGoal -and -not $hasStructuredCleanupSections) {
        $evidence = Get-ClawLatestToolEvidence -Messages $Messages
        if (-not $evidence) {
            return $Content
        }
        $evidencePreview = Get-ClawStructuredEvidencePreview -ToolName $evidence.ToolName -ToolResult $evidence.ToolResult
        if ([string]::IsNullOrWhiteSpace($evidencePreview)) {
            $evidencePreview = 'Use the files already surfaced by the read-only tools as the review set.'
        }
        $riskGuidance = Get-ClawCleanupEvidenceGuidance -ToolName $evidence.ToolName -ToolResult $evidence.ToolResult
        $reviewRanking = Get-ClawCleanupReviewRanking -ToolName $evidence.ToolName -ToolResult $evidence.ToolResult
        $candidateStates = Get-ClawCleanupCandidateStates -ToolName $evidence.ToolName -ToolResult $evidence.ToolResult
        return @"
What I found: $trimmedContent
What looks worth reviewing: $reviewRanking Evidence: $evidencePreview
Candidate states: $candidateStates
What is ambiguous or risky: $riskGuidance
Next safe action: Preview the specific candidate files and confirm before deleting anything.
"@.Trim()
    }

    if ($IsInvestigationGoal -and -not $hasStructuredInvestigationSections) {
        $evidence = Get-ClawLatestToolEvidence -Messages $Messages
        if (-not $evidence) {
            return $Content
        }
        $evidencePreview = Get-ClawStructuredEvidencePreview -ToolName $evidence.ToolName -ToolResult $evidence.ToolResult
        if ([string]::IsNullOrWhiteSpace($evidencePreview)) {
            $evidencePreview = 'Use the source material already gathered.'
        }
        return @"
Answer: $trimmedContent
Evidence: $evidencePreview
Implication: Explain what this means for the current setup or question, and only add a next step if the source material actually calls for one.
"@.Trim()
    }

    if ($IsRecentChangesGoal -and -not $hasStructuredRecentChangesSections) {
        $evidence = Get-ClawLatestToolEvidence -Messages $Messages
        if (-not $evidence) {
            return $Content
        }
        $evidencePreview = Get-ClawStructuredEvidencePreview -ToolName $evidence.ToolName -ToolResult $evidence.ToolResult
        if ([string]::IsNullOrWhiteSpace($evidencePreview)) {
            $evidencePreview = 'Use the recent file and event activity already gathered.'
        }
        return @"
What changed: $trimmedContent
What stands out: $evidencePreview
Implication: Explain whether the surfaced file or event activity looks expected for the requested time window, and call out repeated sources or notable paths when they matter.
Next checks: Use narrower follow-up tools only if the surfaced changes still look abnormal or ambiguous.
"@.Trim()
    }

    return $Content
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
        'Get-CleanupSummary' {
            return @'
schema_version : 1.0
kind           : cleanup_summary
scope          : C:\Users\chris\Downloads
captured_at    : 2026-04-04T18:05:00-05:00
summary        : @{status=actionable; headline=Cleanup candidates were found in Downloads, and some low-risk remnants are execution-allowed after confirmation; candidate_count=3; execution_allowed_count=1}
candidates     : {@{id=candidate:debug_log; state=execution_allowed; category=logs; rank=1}, @{id=candidate:driver-pack_exe; state=review_only; category=installer; rank=2}, @{id=candidate:obs-recording_mp4; state=review_only; category=media; rank=3}}
recommended_order : {candidate:debug_log, candidate:driver-pack_exe, candidate:obs-recording_mp4}
next_action    : @{kind=confirm_delete; reason=Review the ranked candidates, then confirm only the low-risk remnants the user actually wants removed.}
sources        : {@{id=src_search; tool=Search-Files}}
'@
        }
        'Get-SystemTriage' {
            return @'
schema_version : 1.0
kind           : system_triage
host           : DEMO-PC
captured_at    : 2026-04-04T18:05:00-05:00
window_minutes : 60
summary        : @{status=warning; score=40; headline=Memory usage is elevated and Spooler appears unstable}
findings       : {@{id=high_memory:global; severity=warning}, @{id=unstable_service:spooler; severity=warning}}
actions        : {@{id=inspect_memory_top_processes; priority=1}, @{id=confirm_spooler_stability; priority=2}}
sources        : {@{id=src_system; tool=Get-SystemSummary}, @{id=src_services; tool=Get-ServiceStatus}}
'@
        }
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
        'Search-LocalKnowledge' {
            return @'
Collection File Path Line Match LastWritten
documents powerclaw-roadmap.md C:\Users\chris\Documents\powerclaw-roadmap.md 18 PowerClaw native local setup should stay fast 2026-04-04
documents incident-notes.md C:\Users\chris\Documents\incident-notes.md 42 Event Viewer correlation helped isolate the service crash 2026-04-03
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

        $hints.Add('WORKFLOW HINT: For health-check or diagnostic prompts, prefer the most synthesized read-only signal available, then add narrower tools only if the triage leaves something ambiguous or worth confirming.')
        if ('Get-SystemTriage' -in $availableToolNames) {
            $hints.Add('WORKFLOW HINT: For a full health check, start with Get-SystemTriage. It already combines bounded system, process, service, event, and storage signals into one deterministic triage document.')
            if ($healthFollowUps.Count -gt 0) {
                $hints.Add("WORKFLOW HINT: After Get-SystemTriage, use follow-up tools only when the triage points to a specific area worth checking. Useful follow-up signals here: $($healthFollowUps -join ', ').")
            }
        } elseif ('Get-SystemSummary' -in $availableToolNames -and $healthFollowUps.Count -gt 0) {
            $hints.Add("WORKFLOW HINT: For a full health check, start with Get-SystemSummary and usually add at least one complementary tool before answering. Available follow-up signals here: $($healthFollowUps -join ', '). Do not stop after one tool if those extra signals would materially improve confidence.")
        }
        $hints.Add('WORKFLOW HINT: Speed matters. A normal health check should usually finish in 1 to 3 tool calls, not a long chain.')
        $hints.Add('WORKFLOW HINT: Prefer a fast first answer. Only add more tools when the earlier result suggests something abnormal, ambiguous, or worth confirming.')
        $hints.Add('WORKFLOW HINT: For most health checks, prefer triage first, then storage or event issues if needed. Only pull services or network details when the earlier signals suggest a real problem there.')
        $hints.Add('WORKFLOW HINT: For a health check final answer, synthesize into a short operator summary: overall status first, then the most important issues, then concrete next checks if needed.')
        $hints.Add('WORKFLOW HINT: Health-check answers should feel like an operator readout, not a tool dump. Lead with whether the machine looks healthy, degraded, or needs attention.')
        $hints.Add('WORKFLOW HINT: Health-check final answers should usually follow this structure: Overall status, Key findings, Why it matters, Next checks. If nothing looks urgent, say that explicitly instead of sounding alarmed.')
        $hints.Add('WORKFLOW HINT: In Get-SystemTriage, summary.score is a risk score, not a positive health score. A score of 0 means no warning or critical findings were detected in the current window.')
        $hints.Add('WORKFLOW HINT: Do not end a health check with a raw metric dump. Interpret the CPU, memory, storage, network, or service signals into a short operational judgment.')
    }

    if (Test-ClawRecentChangesGoal -UserGoal $UserGoal) {
        $hints.Add('WORKFLOW HINT: For recent-change prompts, prefer one bounded summary of recent files and recent events rather than a long exploratory chain.')
        if ('Get-RecentChangesSummary' -in $availableToolNames) {
            $hints.Add('WORKFLOW HINT: For prompts about what changed recently, start with Get-RecentChangesSummary. It already combines recent file activity with recent system events into one deterministic summary.')
        }
        $hints.Add('WORKFLOW HINT: A normal recent-changes answer should usually finish in 1 to 2 tool calls.')
        $hints.Add('WORKFLOW HINT: Recent-changes final answers should usually follow this order: what changed, what stands out, implication, then next checks only if the surfaced activity looks abnormal.')
        $hints.Add('WORKFLOW HINT: Do not turn a recent-changes answer into a raw timeline dump. Summarize the dominant file paths, event sources, and whether the activity looks expected.')
    }

    if (Test-ClawCleanupGoal -UserGoal $UserGoal) {
        $cleanupContextTools = @(
            'Get-DirectoryListing',
            'Read-FileContent'
        ) | Where-Object { $_ -in $availableToolNames }

        $hints.Add('WORKFLOW HINT: For cleanup and biggest-file prompts, it is acceptable to chain discovery plus context. Find the likely cleanup targets first, then summarize what they are, how large they are, and what you would review before deletion.')
        if ('Get-CleanupSummary' -in $availableToolNames) {
            $hints.Add('WORKFLOW HINT: For a normal cleanup prompt, start with Get-CleanupSummary. It already ranks cleanup candidates, separates review-only items from execution-allowed remnants, and gives the next safe action.')
        } elseif ('Search-Files' -in $availableToolNames) {
            $hints.Add('WORKFLOW HINT: For a normal cleanup prompt, start with Search-Files or another broad discovery tool so the first answer arrives quickly.')
        }
        if ($cleanupContextTools.Count -gt 0) {
            $hints.Add("WORKFLOW HINT: Add context tools such as $($cleanupContextTools -join ', ') only when the first discovery result leaves real ambiguity about what the files are or whether they are worth reviewing.")
        }
        $hints.Add('WORKFLOW HINT: Do not keep issuing broad file-discovery searches with different scopes or sorts. After one broad search, either answer from what you found or use one narrower context tool.')
        $hints.Add('WORKFLOW HINT: Speed matters here too. A normal cleanup answer should usually finish in 1 to 2 tool calls.')
        $hints.Add('WORKFLOW HINT: Cleanup answers should not stop at raw listings. Include a short recommendation section such as what looks safe to review, what is ambiguous, whether the surfaced items are review-only or execution-allowed, and whether the user should preview or confirm anything.')
        $hints.Add('WORKFLOW HINT: Cleanup final answers should usually follow this order: what I found, what looks worth reviewing, candidate states, what is ambiguous or risky, then the next safe action.')
        $hints.Add('WORKFLOW HINT: Do not recommend deletion just because a file is large. Distinguish large-but-likely-intentional files from obvious disposable installers, duplicates, or stale downloads when the evidence supports that distinction.')
        $hints.Add('WORKFLOW HINT: If the evidence is thin, say "worth reviewing" rather than "safe to delete."')
        $hints.Add('WORKFLOW HINT: When possible, explicitly separate likely-intentional files from disposable or stale candidates so the user can see the reasoning, not just the sizes.')
    }

    if (Test-ClawInvestigationGoal -UserGoal $UserGoal) {
        $hints.Add('WORKFLOW HINT: For read, config, log, and webpage investigation prompts, start with a plain-English summary before details.')
        $hints.Add('WORKFLOW HINT: After the summary, pull out the specific settings, warnings, or takeaways that matter. If the content suggests an action, end with the implication or next step.')
        $hints.Add('WORKFLOW HINT: A normal investigation should usually finish in 1 to 2 tool calls. Do not keep opening adjacent files or pages unless the first result leaves a specific ambiguity you need to resolve.')
        $hints.Add('WORKFLOW HINT: Investigation answers should not read like a transcript of file contents or webpage text. Lead with the answer, then cite the settings, warnings, or excerpts that support it.')
        $hints.Add('WORKFLOW HINT: If you already have enough evidence from one source, answer directly instead of exploring sideways for extra context.')
        $hints.Add('WORKFLOW HINT: Investigation final answers should usually follow this order: answer, evidence, implication, and next step only when one is actually warranted by the source.')
        if ('Search-LocalKnowledge' -in $availableToolNames) {
            $hints.Add('WORKFLOW HINT: If the user asks about notes, docs, journals, vault content, or local knowledge, prefer Search-LocalKnowledge before broader file reads.')
        }
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
    $userExplicitlyRequestedPermanentDelete = Test-ClawExplicitPermanentDeleteIntent -UserGoal $UserGoal
    $isHealthCheckGoal = Test-ClawHealthCheckGoal -UserGoal $UserGoal
    $isRecentChangesGoal = (Test-ClawRecentChangesGoal -UserGoal $UserGoal) -and -not $isHealthCheckGoal
    $isCleanupGoal = Test-ClawCleanupGoal -UserGoal $UserGoal
    $isInvestigationGoal = (Test-ClawInvestigationGoal -UserGoal $UserGoal) -and -not $isHealthCheckGoal -and -not $isCleanupGoal -and -not $isRecentChangesGoal
    $planSteps = [System.Collections.Generic.List[object]]::new()
    $planSummary = $null
    $maxPlanPreviewSteps = [Math]::Min($MaxSteps, 3)
    $maxHealthCheckToolCalls = 3
    $maxInvestigationToolCalls = 2
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
            $finalAnswer = Format-ClawFinalAnswer `
                -Content ([string]$response.Content) `
                -Messages $messages `
                -IsHealthCheckGoal $isHealthCheckGoal `
                -IsCleanupGoal $isCleanupGoal `
                -IsInvestigationGoal $isInvestigationGoal `
                -IsRecentChangesGoal $isRecentChangesGoal

            if ($Plan) {
                $planSummary = $finalAnswer
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
                Preview = if ($finalAnswer) { "$finalAnswer".Substring(0, [Math]::Min(200, "$finalAnswer".Length)) } else { '' }
            }
            return $finalAnswer
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
                $toolResult = Format-ClawControlToolResultContent -ControlReason 'repeated_identical_tool_call' -Message "Error: repeated tool call detected for '$toolName' with the same arguments. Do not call the same tool again with identical input. Use the earlier result to answer, or explain why the task cannot continue."
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
                $toolResult = Format-ClawControlToolResultContent -ControlReason 'health_check_latency_budget_reached' -Message "Health-check latency budget reached: you already used $executedReadOnlyToolCount read-only tools for this health check. Answer now from the signals already gathered unless the user explicitly asks for deeper investigation."
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
                (Test-ClawBroadCleanupDiscoveryTool -ToolName $toolName) -and
                @($messages | Where-Object {
                    $_.role -eq 'assistant' -and
                    $_.content -is [array] -and
                    $_.content[0].type -eq 'tool_use' -and
                    (Test-ClawBroadCleanupDiscoveryTool -ToolName ([string]$_.content[0].name))
                }).Count -ge 2
            ) {
                $toolResult = Format-ClawControlToolResultContent -ControlReason 'cleanup_discovery_budget_reached' -Message "Cleanup discovery budget reached: you already used 2 broad read-only discovery tools for this cleanup request. Do not keep searching with new scopes or sorts. Answer now from the files already surfaced, or use a narrower context tool only if the user explicitly asks for deeper inspection."
                Write-Host "[Latency] Cleanup discovery budget reached; asking model to stop broad searching." -ForegroundColor Yellow
                Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                    Event      = 'tool_skipped'
                    Step       = $step
                    Outcome    = 'blocked'
                    Tool       = $toolName
                    ToolUseId  = $response.ToolUseId
                    Reason     = 'cleanup_discovery_budget_reached'
                    UserGoal   = $UserGoal
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
                $toolResult = Format-ClawControlToolResultContent -ControlReason 'cleanup_latency_budget_reached' -Message "Cleanup latency budget reached: you already used $executedReadOnlyToolCount read-only tools for this cleanup request. Answer now from the files and context already gathered unless the user explicitly asks for deeper inspection."
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

            if (
                -not $Plan -and
                $isInvestigationGoal -and
                $tool.Risk -eq 'ReadOnly' -and
                $executedReadOnlyToolCount -ge $maxInvestigationToolCalls
            ) {
                $toolResult = Format-ClawControlToolResultContent -ControlReason 'investigation_latency_budget_reached' -Message "Investigation latency budget reached: you already used $executedReadOnlyToolCount read-only tools for this investigation. Answer now from the source material already gathered unless the user explicitly asks for a broader comparison."
                Write-Host "[Latency] Investigation tool budget reached; asking model to answer from current evidence." -ForegroundColor Yellow
                Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                    Event      = 'tool_skipped'
                    Step       = $step
                    Outcome    = 'blocked'
                    Tool       = $toolName
                    ToolUseId  = $response.ToolUseId
                    Reason     = 'investigation_latency_budget_reached'
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

                $planToolResult = Format-ClawControlToolResultContent -ControlReason 'plan_preview_only' -Message "Plan preview only: $toolName was not executed. Continue by previewing the next intended step or return a concise plan summary based on the intended chain so far. Do not assume real tool output."
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
                    $toolResult = Format-ClawPolicyToolResultContent -PolicyReason 'explicit_write_intent_required' -Message "Blocked by write policy: the user goal did not explicitly ask for a destructive change. Ask for confirmation in plain language first, or continue with read-only investigation."
                    Write-Host "[Blocked] $toolName requires an explicit user request for changes." -ForegroundColor Yellow
                    Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                        Event      = 'tool_skipped'
                        Step       = $step
                        Outcome    = 'blocked'
                        Tool       = $toolName
                        ToolUseId  = $response.ToolUseId
                        Reason     = 'write_policy_blocked'
                        PolicyReason = (Get-ClawWritePolicyReason -Reason 'write_policy_blocked')
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
                    $toolResult = Format-ClawPolicyToolResultContent -PolicyReason 'prior_evidence_required' -Message "Blocked by write policy: Remove-Files may only run on exact paths that were already shown in earlier read-only results during this request. First enumerate the candidate files with a read-only tool, then ask again with those same full paths."
                    Write-Host "[Blocked] $toolName requires evidence-backed file targets before deletion." -ForegroundColor Yellow
                    Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                        Event      = 'tool_skipped'
                        Step       = $step
                        Outcome    = 'blocked'
                        Tool       = $toolName
                        ToolUseId  = $response.ToolUseId
                        Reason     = 'write_targets_not_previously_enumerated'
                        PolicyReason = (Get-ClawWritePolicyReason -Reason 'write_targets_not_previously_enumerated')
                        Risk       = $tool.Risk
                        Args       = $toolInput
                        UserGoal   = $UserGoal
                    }
                    $messages = Add-ClawToolResultTurn -Messages $messages -ToolUseId $response.ToolUseId -ToolName $toolName -ToolInput $toolInput -Content $toolResult
                    continue
                }

                if (
                    $toolName -eq 'Remove-Files' -and
                    $toolInput -and
                    $toolInput.ContainsKey('Permanent') -and
                    [bool]$toolInput.Permanent -and
                    -not $userExplicitlyRequestedPermanentDelete
                ) {
                    $toolResult = Format-ClawPolicyToolResultContent -PolicyReason 'explicit_permanent_intent_required' -Message "Blocked by write policy: permanent deletion requires explicit permanent intent from the user. Ask the user to say plainly that they want a permanent delete or a recycle-bin delete."
                    Write-Host "[Blocked] $toolName permanent delete requires explicit permanent intent." -ForegroundColor Yellow
                    Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                        Event      = 'tool_skipped'
                        Step       = $step
                        Outcome    = 'blocked'
                        Tool       = $toolName
                        ToolUseId  = $response.ToolUseId
                        Reason     = 'permanent_delete_intent_not_explicit'
                        PolicyReason = (Get-ClawWritePolicyReason -Reason 'permanent_delete_intent_not_explicit')
                        Risk       = $tool.Risk
                        Args       = $toolInput
                        UserGoal   = $UserGoal
                    }
                    $messages = Add-ClawToolResultTurn -Messages $messages -ToolUseId $response.ToolUseId -ToolName $toolName -ToolInput $toolInput -Content $toolResult
                    continue
                }

                if (
                    $toolName -eq 'Remove-Files' -and
                    (Test-ClawDeleteTargetsNeedSpecificReference -ToolInput $toolInput) -and
                    -not (Test-ClawGoalReferencesDeleteTargetsSpecifically -UserGoal $UserGoal -ToolInput $toolInput)
                ) {
                    $toolResult = Format-ClawPolicyToolResultContent -PolicyReason 'specific_user_reference_required' -Message "Blocked by write policy: this delete request targets file types that need a more specific user instruction. Ask the user to name the exact file, path, or file type they want removed instead of relying on a vague reference like 'that file'."
                    Write-Host "[Blocked] $toolName sensitive target requires a more specific user reference." -ForegroundColor Yellow
                    Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                        Event      = 'tool_skipped'
                        Step       = $step
                        Outcome    = 'blocked'
                        Tool       = $toolName
                        ToolUseId  = $response.ToolUseId
                        Reason     = 'delete_target_reference_not_specific_enough'
                        PolicyReason = (Get-ClawWritePolicyReason -Reason 'delete_target_reference_not_specific_enough')
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
                    $toolResult = Format-ClawPolicyToolResultContent -PolicyReason 'execution_mode_dry_run' -Message "(dry run — not executed)"
                    Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                        Event     = 'tool_skipped'
                        Step      = $step
                        Outcome   = 'dry_run'
                        Tool      = $toolName
                        ToolUseId = $response.ToolUseId
                        Reason    = 'dry_run'
                        PolicyReason = (Get-ClawWritePolicyReason -Reason 'dry_run')
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
                        $toolResult = Format-ClawPolicyToolResultContent -PolicyReason 'confirmation_declined' -Message "User declined to run $toolName. Confirmation token '$confirmToken' was not provided."
                        Write-ClawLoopLogEntry -LogPath $logPath -Entry @{
                            Event             = 'tool_skipped'
                            Step              = $step
                            Outcome           = 'declined'
                            Tool              = $toolName
                            ToolUseId         = $response.ToolUseId
                            Reason            = 'confirmation_declined'
                            PolicyReason      = (Get-ClawWritePolicyReason -Reason 'confirmation_declined')
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

                if ($tool.Risk -eq 'Write') {
                    $toolResult = Format-ClawPolicyToolResultContent -PolicyReason 'confirmed_write_execution' -Message $toolResult
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
                PolicyReason  = if ($tool.Risk -eq 'Write') { 'confirmed_write_execution' } else { $null }
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
