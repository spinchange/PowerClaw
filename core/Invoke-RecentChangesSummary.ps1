function Invoke-RecentChangesSummary {
    [CmdletBinding()]
    param(
        [string]$Scope = $env:USERPROFILE,

        [ValidateRange(1, 168)]
        [int]$HoursBack = 24,

        [ValidateRange(1, 25)]
        [int]$Limit = 10,

        [ValidateRange(1, 100)]
        [int]$EventLimit = 50,

        [switch]$AsJson
    )

    $capturedAt = [datetimeoffset]::Now
    $after = $capturedAt.AddHours(-$HoursBack).DateTime
    $collectorWarnings = [System.Collections.Generic.List[string]]::new()

    $searchFilesCommand = Get-Command -Name 'Search-Files' -ErrorAction SilentlyContinue
    $eventLogCommand = Get-Command -Name 'Get-EventLogEntries' -ErrorAction SilentlyContinue

    $fileResults = @()
    if ($searchFilesCommand) {
        try {
            $fileResults = @(
                Search-Files -Scope $Scope -SortBy DateModified -Limit ([Math]::Max($Limit, 25)) -After $after
            )
        }
        catch {
            $collectorWarnings.Add("Recent file activity could not be summarized because Search-Files failed: $($_.Exception.Message)") | Out-Null
        }
    }
    else {
        $collectorWarnings.Add('Recent file activity could not be summarized because Search-Files is not loaded in the current session.') | Out-Null
    }

    $eventResults = @()
    if ($eventLogCommand) {
        try {
            $eventResults = @(
                Get-EventLogEntries -LogName System -Level All -HoursBack $HoursBack -Limit $EventLimit
            )
        }
        catch {
            $collectorWarnings.Add("Recent system events could not be summarized because Get-EventLogEntries failed: $($_.Exception.Message)") | Out-Null
        }
    }
    else {
        $collectorWarnings.Add('Recent system events could not be summarized because Get-EventLogEntries is not loaded in the current session.') | Out-Null
    }

    $recentFiles = @(
        $fileResults |
            Where-Object { $_.PSObject.Properties.Name -contains 'Path' } |
            Select-Object -First $Limit -Property Name, Path, SizeMB, DateModified
    )

    $recentEvents = @(
        $eventResults |
            Where-Object { $_.PSObject.Properties.Name -contains 'Source' } |
            Select-Object -First $Limit -Property TimeCreated, Level, Source, EventId, Message
    )

    $eventSourceSummary = @(
        $recentEvents |
            Group-Object Source |
            Sort-Object Count -Descending |
            Select-Object -First 5 |
            ForEach-Object {
                $latestTime = @($_.Group | ForEach-Object { $_.TimeCreated } | Select-Object -First 1)[0]
                [PSCustomObject]@{
                    Source          = $_.Name
                    Count           = $_.Count
                    LatestEventTime = $latestTime
                }
            }
    )

    $headline = if ($collectorWarnings.Count -gt 0 -and $recentFiles.Count -eq 0 -and $recentEvents.Count -eq 0) {
        $collectorWarnings[0]
    }
    elseif ($collectorWarnings.Count -gt 0 -and $recentFiles.Count -eq 0) {
        "Partial recent-changes summary for the last $HoursBack hours: $($recentEvents.Count) recent events were surfaced, but recent file activity is unavailable."
    }
    elseif ($collectorWarnings.Count -gt 0 -and $recentEvents.Count -eq 0) {
        "Partial recent-changes summary for the last $HoursBack hours: $($recentFiles.Count) recent file updates were surfaced, but recent system events are unavailable."
    }
    elseif ($recentFiles.Count -eq 0 -and $recentEvents.Count -eq 0) {
        "No recent file or event changes were surfaced in the last $HoursBack hours."
    }
    elseif ($recentFiles.Count -gt 0 -and $recentEvents.Count -gt 0) {
        $topSource = if ($eventSourceSummary.Count -gt 0) { $eventSourceSummary[0].Source } else { 'system events' }
        "Recent changes in the last $HoursBack hours include $($recentFiles.Count) surfaced files and $($recentEvents.Count) recent events, led by $topSource."
    }
    elseif ($recentFiles.Count -gt 0) {
        "Recent changes in the last $HoursBack hours are dominated by $($recentFiles.Count) surfaced file updates."
    }
    else {
        $topSource = if ($eventSourceSummary.Count -gt 0) { $eventSourceSummary[0].Source } else { 'system events' }
        "Recent changes in the last $HoursBack hours are dominated by $($recentEvents.Count) system events, led by $topSource."
    }

    $doc = [PSCustomObject]@{
        kind                 = 'recent_changes_summary'
        captured_at          = $capturedAt.ToString('o')
        scope                = $Scope
        window_hours         = $HoursBack
        summary              = [PSCustomObject]@{
            headline             = $headline
            recent_file_count    = $recentFiles.Count
            recent_event_count   = $recentEvents.Count
            dominant_event_source = if ($eventSourceSummary.Count -gt 0) { $eventSourceSummary[0].Source } else { $null }
        }
        recent_files         = @($recentFiles)
        recent_event_sources = @($eventSourceSummary)
        recent_events        = @($recentEvents)
        sources              = @(
            if ($searchFilesCommand) {
                [PSCustomObject]@{
                    tool        = 'Search-Files'
                    scope       = $Scope
                    captured_at = $capturedAt.ToString('o')
                    window      = "last_${HoursBack}_hours"
                }
            }
            if ($eventLogCommand) {
                [PSCustomObject]@{
                    tool        = 'Get-EventLogEntries'
                    scope       = 'System'
                    captured_at = $capturedAt.ToString('o')
                    window      = "last_${HoursBack}_hours"
                }
            }
        )
    }

    if ($AsJson) {
        return $doc | ConvertTo-Json -Depth 8
    }

    return $doc
}
