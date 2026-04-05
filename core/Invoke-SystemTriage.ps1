function ConvertTo-SystemTriageNormalizedInput {
    [CmdletBinding()]
    param(
        [object]$SystemSummary,
        [object[]]$TopCpuProcesses,
        [object[]]$TopMemoryProcesses,
        [object[]]$ServiceStatus,
        [object[]]$EventLogEntries,
        [object]$StorageStatus,
        [datetimeoffset]$CapturedAt = [datetimeoffset]::Now
    )

    $systemNode = if ($SystemSummary -and $SystemSummary.PSObject.Properties.Name -contains 'System') { $SystemSummary.System } else { $SystemSummary }
    $hostName = $null
    if ($systemNode) {
        $hostName = [string]($systemNode.MachineName ?? $systemNode.Host ?? $env:COMPUTERNAME)
        if ($hostName -match '\.') { $hostName = ($hostName -split '\.')[0] }
    }

    $uptimeHours = $null
    if ($systemNode -and $systemNode.PSObject.Properties.Name -contains 'Uptime') {
        $m = [regex]::Match([string]$systemNode.Uptime, '^(?:(?<d>\d+)d\s*)?(?:(?<h>\d+)h\s*)?(?:(?<m>\d+)m)?$')
        if ($m.Success) {
            $days = if ($m.Groups['d'].Success) { [int]$m.Groups['d'].Value } else { 0 }
            $hours = if ($m.Groups['h'].Success) { [int]$m.Groups['h'].Value } else { 0 }
            $minutes = if ($m.Groups['m'].Success) { [int]$m.Groups['m'].Value } else { 0 }
            $uptimeHours = [math]::Round(($days * 24) + $hours + ($minutes / 60.0), 2)
        }
    }

    $storageDrives = if ($StorageStatus -and $StorageStatus.PSObject.Properties.Name -contains 'Drives') {
        @($StorageStatus.Drives)
    } elseif ($StorageStatus -is [System.Collections.IEnumerable] -and $StorageStatus -isnot [string]) {
        @($StorageStatus)
    } elseif ($StorageStatus) {
        @($StorageStatus)
    } else {
        @()
    }

    [PSCustomObject]@{
        host = if ($hostName) { $hostName } else { [string]$env:COMPUTERNAME }
        captured_at = $CapturedAt.ToString('o')
        system = if ($systemNode) {
            [PSCustomObject]@{
                cpu_pct = if ($systemNode.PSObject.Properties.Name -contains 'CPULoadPct') { [math]::Round([double]$systemNode.CPULoadPct, 1) } else { $null }
                memory_pct = if ($systemNode.PSObject.Properties.Name -contains 'RAMUsedPct') { [math]::Round([double]$systemNode.RAMUsedPct, 1) } else { $null }
                uptime_hours = $uptimeHours
            }
        } else { $null }
        top_processes = [PSCustomObject]@{
            cpu = @($TopCpuProcesses | Select-Object -First 1 | ForEach-Object {
                [PSCustomObject]@{ name = [string]$_.Name; cpu_pct = if ($_.PSObject.Properties.Name -contains 'CPU') { [math]::Round([double]$_.CPU, 1) } else { $null } }
            }) | Select-Object -First 1
            memory = @($TopMemoryProcesses | Select-Object -First 1 | ForEach-Object {
                [PSCustomObject]@{ name = [string]$_.Name; mem_mb = if ($_.PSObject.Properties.Name -contains 'MemoryMB') { [math]::Round([double]$_.MemoryMB, 1) } else { $null } }
            }) | Select-Object -First 1
        }
        volumes = @(
            $storageDrives |
                Where-Object { $_.Drive } |
                ForEach-Object {
                    $driveName = ([string]$_.Drive).TrimEnd(':')
                    [PSCustomObject]@{
                        name = $driveName
                        free_pct = if ($_.PSObject.Properties.Name -contains 'PercentFull') { [math]::Round(100 - [double]$_.PercentFull, 1) } else { $null }
                        free_gb = if ($_.PSObject.Properties.Name -contains 'FreeGB') { [math]::Round([double]$_.FreeGB, 1) } else { $null }
                        kind = 'fixed'
                        is_system = $driveName -eq 'C'
                    }
                }
        )
        services = @(
            @($ServiceStatus) |
                Where-Object { $_.Name } |
                ForEach-Object {
                    [PSCustomObject]@{
                        name = [string]$_.Name
                        state = switch -Regex ([string]$_.Status) {
                            '^Running$' { 'running' }
                            '^Stopped$' { 'stopped' }
                            '^Paused$' { 'paused' }
                            default { 'other' }
                        }
                        startup = switch -Regex ([string]$_.StartType) {
                            '^Auto' { 'automatic' }
                            '^Manual' { 'manual' }
                            '^Disabled' { 'disabled' }
                            default { 'unknown' }
                        }
                        recent_failure_signal = (([string]$_.Status) -eq 'Stopped' -and ([string]$_.StartType) -match '^Auto')
                        failure_count = 0
                    }
                }
        )
        event_sources = @(
            @($EventLogEntries) |
                Where-Object { $_.Source } |
                Group-Object -Property { [regex]::Replace(([string]$_.Source).Trim(), '\s+', ' ') } |
                ForEach-Object {
                    $group = @($_.Group)
                    [PSCustomObject]@{
                        source = [string]$_.Name
                        warning_error_count = @($group | Where-Object { $_.Level -in @('Warning', 'Error', 'Critical') }).Count
                        error_count = @($group | Where-Object { $_.Level -in @('Error', 'Critical') }).Count
                    }
                }
        )
    }
}

function Invoke-SystemTriage {
    [CmdletBinding()]
    param(
        [switch]$AsJson
    )

    $capturedAt = [datetimeoffset]::Now
    $collectorResults = [ordered]@{
        SystemSummary = $null
        TopCpuProcesses = @()
        TopMemoryProcesses = @()
        ServiceStatus = @()
        EventLogEntries = @()
        StorageStatus = $null
    }
    $sources = [System.Collections.Generic.List[object]]::new()

    $collectors = @(
        [PSCustomObject]@{
            Key = 'SystemSummary'
            SourceId = 'src_system'
            Tool = 'Get-SystemSummary'
            Scope = 'local_host'
            Action = { Get-SystemSummary -View Quick }
        }
        [PSCustomObject]@{
            Key = 'TopProcesses'
            SourceId = 'src_processes'
            Tool = 'Get-TopProcesses'
            Scope = 'top_processes'
            Action = {
                @{
                    Cpu = @(Get-TopProcesses -SortBy CPU -Count 1)
                    Memory = @(Get-TopProcesses -SortBy Memory -Count 1)
                }
            }
        }
        [PSCustomObject]@{
            Key = 'ServiceStatus'
            SourceId = 'src_services'
            Tool = 'Get-ServiceStatus'
            Scope = 'important_services'
            Action = { @(Get-ServiceStatus -Filter All -StartType Any -Limit 200) }
        }
        [PSCustomObject]@{
            Key = 'EventLogEntries'
            SourceId = 'src_events'
            Tool = 'Get-EventLogEntries'
            Scope = 'last_60_minutes'
            Action = { @(Get-EventLogEntries -LogName System -Level All -HoursBack 1 -Limit 100) }
        }
        [PSCustomObject]@{
            Key = 'StorageStatus'
            SourceId = 'src_storage'
            Tool = 'Get-StorageStatus'
            Scope = 'fixed_volumes'
            Action = { Get-StorageStatus -View Drives }
        }
    )

    foreach ($collector in $collectors) {
        try {
            $result = & $collector.Action
            switch ($collector.Key) {
                'SystemSummary' { $collectorResults.SystemSummary = $result }
                'TopProcesses' {
                    $collectorResults.TopCpuProcesses = @($result.Cpu)
                    $collectorResults.TopMemoryProcesses = @($result.Memory)
                }
                'ServiceStatus' { $collectorResults.ServiceStatus = @($result) }
                'EventLogEntries' { $collectorResults.EventLogEntries = @($result) }
                'StorageStatus' { $collectorResults.StorageStatus = $result }
            }

            $sources.Add([PSCustomObject]@{
                id = $collector.SourceId
                tool = $collector.Tool
                captured_at = $capturedAt.ToString('o')
                scope = $collector.Scope
            }) | Out-Null
        }
        catch {
            continue
        }
    }

    $normalized = ConvertTo-SystemTriageNormalizedInput `
        -SystemSummary $collectorResults.SystemSummary `
        -TopCpuProcesses $collectorResults.TopCpuProcesses `
        -TopMemoryProcesses $collectorResults.TopMemoryProcesses `
        -ServiceStatus $collectorResults.ServiceStatus `
        -EventLogEntries $collectorResults.EventLogEntries `
        -StorageStatus $collectorResults.StorageStatus `
        -CapturedAt $capturedAt

    $document = New-SystemTriageDocument -NormalizedInput $normalized -Sources @($sources)
    if ($AsJson) {
        return $document | ConvertTo-Json -Depth 10
    }

    return $document
}

function New-SystemTriageDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$NormalizedInput,

        [object[]]$Sources
    )

    $severityRank = @{ critical = 3; warning = 2; info = 1 }
    $actionabilityRank = @{ low_disk = 6; unstable_service = 5; high_memory = 4; high_cpu = 3; repeated_system_errors = 2; abnormal_uptime_signal = 1 }
    $serviceAllowlist = @('LanmanServer', 'Dnscache', 'EventLog', 'WinDefend', 'W32Time', 'wuauserv', 'Spooler')

    function Format-SystemTriageNumber { param([double]$Value) if ([math]::Abs($Value - [math]::Round($Value)) -lt 0.001) { [string][int][math]::Round($Value) } else { '{0:0.0}' -f $Value } }
    function Get-SystemTriageIdSegment { param([string]$Value) $n = [regex]::Replace((($Value ?? '').Trim().ToLowerInvariant()), '\s+', '_'); $n = $n.Replace(':', ''); [regex]::Replace($n, '[^a-z0-9_-]', '') }
    function Get-SystemTriageDefaultSources {
        param([object]$InputObject)
        $capturedAt = [string]($InputObject.captured_at ?? ([datetimeoffset]::Now.ToString('o')))
        $result = [System.Collections.Generic.List[object]]::new()
        if ($InputObject.system) { $result.Add([PSCustomObject]@{ id = 'src_system'; tool = 'Get-SystemSummary'; captured_at = $capturedAt; scope = 'local_host' }) | Out-Null }
        if ($InputObject.top_processes -and ($InputObject.top_processes.cpu -or $InputObject.top_processes.memory)) { $result.Add([PSCustomObject]@{ id = 'src_processes'; tool = 'Get-TopProcesses'; captured_at = $capturedAt; scope = 'top_processes' }) | Out-Null }
        if (@($InputObject.services).Count -gt 0) { $result.Add([PSCustomObject]@{ id = 'src_services'; tool = 'Get-ServiceStatus'; captured_at = $capturedAt; scope = 'important_services' }) | Out-Null }
        if (@($InputObject.event_sources).Count -gt 0) { $result.Add([PSCustomObject]@{ id = 'src_events'; tool = 'Get-EventLogEntries'; captured_at = $capturedAt; scope = 'last_60_minutes' }) | Out-Null }
        if (@($InputObject.volumes).Count -gt 0) { $result.Add([PSCustomObject]@{ id = 'src_storage'; tool = 'Get-StorageStatus'; captured_at = $capturedAt; scope = 'fixed_volumes' }) | Out-Null }
        @($result)
    }

    $allSources = if ($PSBoundParameters.ContainsKey('Sources')) { @($Sources) } else { @(Get-SystemTriageDefaultSources -InputObject $NormalizedInput) }
    $availableSourceIds = @($allSources | ForEach-Object { [string]$_.id })
    $findings = [System.Collections.Generic.List[object]]::new()

    if ($NormalizedInput.system -and $NormalizedInput.system.cpu_pct -ne $null -and 'src_system' -in $availableSourceIds) {
        $cpuPct = [double]$NormalizedInput.system.cpu_pct
        if ($cpuPct -ge 70) {
            $severity = if ($cpuPct -ge 90) { 'critical' } else { 'warning' }
            $evidence = [System.Collections.Generic.List[string]]::new()
            $refs = [System.Collections.Generic.List[string]]::new()
            $evidence.Add("CPU in use: $(Format-SystemTriageNumber $cpuPct)%") | Out-Null
            $refs.Add('src_system') | Out-Null
            if ($NormalizedInput.top_processes -and $NormalizedInput.top_processes.cpu -and $NormalizedInput.top_processes.cpu.name -and 'src_processes' -in $availableSourceIds) {
                $evidence.Add("Top CPU process: $($NormalizedInput.top_processes.cpu.name) at $(Format-SystemTriageNumber ([double]($NormalizedInput.top_processes.cpu.cpu_pct ?? 0)))%") | Out-Null
                $refs.Add('src_processes') | Out-Null
            }
            $findings.Add([PSCustomObject]@{ id = 'high_cpu:global'; type = 'high_cpu'; severity = $severity; category = 'cpu'; title = if ($severity -eq 'critical') { 'CPU usage is critical' } else { 'CPU usage is elevated' }; reason = if ($severity -eq 'critical') { 'Current CPU usage is above the critical threshold' } else { 'Current CPU usage is above the warning threshold' }; evidence = @($evidence); confidence = 0.95; source_refs = @($refs) }) | Out-Null
        }
    }

    if ($NormalizedInput.system -and $NormalizedInput.system.memory_pct -ne $null -and 'src_system' -in $availableSourceIds) {
        $memoryPct = [double]$NormalizedInput.system.memory_pct
        if ($memoryPct -ge 80) {
            $severity = if ($memoryPct -ge 92) { 'critical' } else { 'warning' }
            $evidence = [System.Collections.Generic.List[string]]::new()
            $refs = [System.Collections.Generic.List[string]]::new()
            $evidence.Add("Memory in use: $(Format-SystemTriageNumber $memoryPct)%") | Out-Null
            $refs.Add('src_system') | Out-Null
            if ($NormalizedInput.top_processes -and $NormalizedInput.top_processes.memory -and $NormalizedInput.top_processes.memory.name -and 'src_processes' -in $availableSourceIds) {
                $evidence.Add("Top memory process: $($NormalizedInput.top_processes.memory.name) at $(Format-SystemTriageNumber ([double]($NormalizedInput.top_processes.memory.mem_mb ?? 0))) MB") | Out-Null
                $refs.Add('src_processes') | Out-Null
            }
            $findings.Add([PSCustomObject]@{ id = 'high_memory:global'; type = 'high_memory'; severity = $severity; category = 'memory'; title = if ($severity -eq 'critical') { 'Memory usage is critical' } else { 'Memory usage is elevated' }; reason = if ($severity -eq 'critical') { 'Current memory usage is above the critical threshold' } else { 'Current memory usage is above the warning threshold' }; evidence = @($evidence); confidence = 0.95; source_refs = @($refs) }) | Out-Null
        }
    }

    if (@($NormalizedInput.volumes).Count -gt 0 -and 'src_storage' -in $availableSourceIds) {
        $diskCandidate = @($NormalizedInput.volumes | Where-Object { $_.free_pct -ne $null -and [double]$_.free_pct -le 20 } | Sort-Object @{ Expression = { if ([double]$_.free_pct -le 10) { 0 } else { 1 } } }, @{ Expression = { [double]$_.free_pct } }, @{ Expression = { [double]($_.free_gb ?? [double]::PositiveInfinity) } }, @{ Expression = { if ($_.is_system) { 0 } else { 1 } } }, @{ Expression = { [string]$_.name } } | Select-Object -First 1)
        if ($diskCandidate) {
            $volume = $diskCandidate[0]
            $severity = if ([double]$volume.free_pct -le 10) { 'critical' } else { 'warning' }
            $evidence = @("Volume $($volume.name) free space: $(Format-SystemTriageNumber ([double]$volume.free_pct))%")
            if ($volume.free_gb -ne $null) { $evidence += "Free space remaining: $(Format-SystemTriageNumber ([double]$volume.free_gb)) GB" }
            $findings.Add([PSCustomObject]@{ id = "low_disk:$((Get-SystemTriageIdSegment $volume.name))"; type = 'low_disk'; severity = $severity; category = 'disk'; title = "Disk free space is low on $($volume.name)"; reason = if ($severity -eq 'critical') { 'Available disk space on the selected volume is below the critical threshold' } else { 'Available disk space on the selected volume is below the warning threshold' }; evidence = @($evidence); confidence = 0.98; source_refs = @('src_storage') }) | Out-Null
        }
    }

    if (@($NormalizedInput.services).Count -gt 0 -and 'src_services' -in $availableSourceIds) {
        $qualifyingServices = @($NormalizedInput.services | Where-Object { $_.name -in $serviceAllowlist } | Where-Object { [int]($_.failure_count ?? 0) -ge 1 -or $_.recent_failure_signal -eq $true -or ($_.state -ne 'running' -and $_.startup -eq 'automatic') } | Sort-Object @{ Expression = { [string]$_.name } })
        if ($qualifyingServices.Count -ge 2) {
            $affectedServices = @($qualifyingServices | ForEach-Object { [string]$_.name } | Sort-Object)
            $refs = @('src_services')
            if ('src_events' -in $availableSourceIds) { $refs += 'src_events' }
            $findings.Add([PSCustomObject]@{ id = 'unstable_service:multiple'; type = 'unstable_service'; severity = 'critical'; category = 'service'; title = 'Multiple important services appear unstable'; reason = 'More than one important service showed instability during the observation window'; evidence = @("Unstable important services: $($affectedServices.Count)", "Affected services: $($affectedServices -join ', ')"); confidence = 0.90; source_refs = @($refs) }) | Out-Null
        } elseif ($qualifyingServices.Count -eq 1) {
            $service = $qualifyingServices[0]
            $failureCount = [int]($service.failure_count ?? 0)
            $severity = if ($failureCount -ge 2) { 'critical' } else { 'warning' }
            $confidence = if ($failureCount -ge 2 -and 'src_events' -in $availableSourceIds) { 0.90 } elseif (($service.recent_failure_signal -eq $true -or $failureCount -ge 1) -and 'src_events' -in $availableSourceIds) { 0.85 } else { 0.80 }
            $evidence = [System.Collections.Generic.List[string]]::new()
            $refs = [System.Collections.Generic.List[string]]::new()
            $evidence.Add("Service state: $($service.state)") | Out-Null
            if ($failureCount -ge 1) { $evidence.Add("Recent failure signals: $failureCount") | Out-Null }
            $refs.Add('src_services') | Out-Null
            if ('src_events' -in $availableSourceIds) { $evidence.Add('Recent service-related event activity was observed') | Out-Null; $refs.Add('src_events') | Out-Null }
            $findings.Add([PSCustomObject]@{ id = "unstable_service:$((Get-SystemTriageIdSegment $service.name))"; type = 'unstable_service'; severity = $severity; category = 'service'; title = "$($service.name) appears unstable"; reason = if ($severity -eq 'critical') { 'The service showed repeated instability signals during the observation window' } else { 'The service showed a recent instability signal during the observation window' }; evidence = @($evidence); confidence = $confidence; source_refs = @($refs) }) | Out-Null
        }
    }

    if (@($NormalizedInput.event_sources).Count -gt 0 -and 'src_events' -in $availableSourceIds) {
        $eventCandidate = @($NormalizedInput.event_sources | Where-Object { [int]($_.warning_error_count ?? 0) -ge 5 -or [int]($_.error_count ?? 0) -ge 10 } | Sort-Object @{ Expression = { -[int]($_.warning_error_count ?? 0) } }, @{ Expression = { -[int]($_.error_count ?? 0) } }, @{ Expression = { Get-SystemTriageIdSegment ([string]$_.source) } } | Select-Object -First 1)
        if ($eventCandidate) {
            $source = $eventCandidate[0]
            $severity = if ([int]($source.error_count ?? 0) -ge 10) { 'critical' } else { 'warning' }
            $evidence = @("$([int]$source.warning_error_count) warnings/errors from $($source.source) in 60 minutes")
            if ([int]($source.error_count ?? 0) -gt 0) { $evidence += "$([int]$source.error_count) were error-level events" }
            $findings.Add([PSCustomObject]@{ id = "repeated_system_errors:$((Get-SystemTriageIdSegment $source.source))"; type = 'repeated_system_errors'; severity = $severity; category = 'eventlog'; title = "Recent system errors are concentrated in $($source.source)"; reason = if ($severity -eq 'critical') { 'Repeated error-level activity from one source exceeded the critical threshold' } else { 'Warning and error activity from one source exceeded the warning threshold' }; evidence = @($evidence); confidence = if ($severity -eq 'critical') { 0.85 } else { 0.70 }; source_refs = @('src_events') }) | Out-Null
        }
    }

    if (@($findings).Count -gt 0 -and $NormalizedInput.system -and $NormalizedInput.system.uptime_hours -ne $null -and 'src_system' -in $availableSourceIds) {
        $uptimeHours = [double]$NormalizedInput.system.uptime_hours
        if ($uptimeHours -lt 2 -or $uptimeHours -gt 720) {
            $severity = if ($uptimeHours -gt 720) { 'warning' } else { 'info' }
            $evidence = if ($uptimeHours -gt 720) { @("Current uptime: $(Format-SystemTriageNumber ([math]::Round($uptimeHours / 24, 1))) days") } else { @("Current uptime: $(Format-SystemTriageNumber $uptimeHours) hours") }
            $findings.Add([PSCustomObject]@{ id = 'abnormal_uptime_signal:global'; type = 'abnormal_uptime_signal'; severity = $severity; category = 'uptime'; title = 'System uptime may explain current conditions'; reason = if ($severity -eq 'warning') { 'Extended uptime may be contributing to current instability signals' } else { 'The system restarted recently and some current signals may be post-boot effects' }; evidence = @($evidence); confidence = 0.90; source_refs = @('src_system') }) | Out-Null
        }
    }

    $sortedFindings = @($findings | Sort-Object @{ Expression = { -$severityRank[$_.severity] } }, @{ Expression = { -[double]$_.confidence } }, @{ Expression = { -$actionabilityRank[$_.type] } }, @{ Expression = { [string]$_.id } } | Select-Object -First 10)

    $actionTemplates = foreach ($finding in $sortedFindings) {
        switch ($finding.type) {
            'high_cpu' { [PSCustomObject]@{ id = 'inspect_cpu_processes'; kind = 'inspect'; target = 'processes'; reason = 'Review the top CPU consumers to identify avoidable load'; related_finding_ids = @($finding.id); severity = $finding.severity; confidence = $finding.confidence; finding_type = $finding.type } }
            'high_memory' { [PSCustomObject]@{ id = 'inspect_memory_top_processes'; kind = 'inspect'; target = 'processes'; reason = 'Review the top memory consumers to identify avoidable pressure'; related_finding_ids = @($finding.id); severity = $finding.severity; confidence = $finding.confidence; finding_type = $finding.type } }
            'low_disk' {
                $volume = ($finding.id -split ':', 2)[1].ToUpperInvariant()
                [PSCustomObject]@{ id = "inspect_volume_$volume"; kind = 'inspect'; target = "volume:$volume"; reason = 'Review large consumers on the affected volume before space becomes critical'; related_finding_ids = @($finding.id); severity = $finding.severity; confidence = $finding.confidence; finding_type = $finding.type }
            }
            'unstable_service' {
                if ($finding.id -eq 'unstable_service:multiple') {
                    [PSCustomObject]@{ id = 'escalate_service_instability'; kind = 'escalate'; target = 'services'; reason = 'Multiple important services show instability and should be reviewed together'; related_finding_ids = @($finding.id); severity = $finding.severity; confidence = $finding.confidence; finding_type = $finding.type }
                } else {
                    $serviceSegment = ($finding.id -split ':', 2)[1]
                    $serviceName = $finding.title -replace ' appears unstable$', ''
                    [PSCustomObject]@{ id = "confirm_${serviceSegment}_stability"; kind = 'confirm'; target = "service:$serviceName"; reason = 'Confirm whether the service instability is ongoing or user-impacting'; related_finding_ids = @($finding.id); severity = $finding.severity; confidence = $finding.confidence; finding_type = $finding.type }
                }
            }
            'repeated_system_errors' {
                $sourceSegment = ($finding.id -split ':', 2)[1]
                [PSCustomObject]@{ id = "inspect_event_source_$sourceSegment"; kind = 'inspect'; target = "event_source:$sourceSegment"; reason = 'Review repeated recent errors from the dominant event source'; related_finding_ids = @($finding.id); severity = $finding.severity; confidence = $finding.confidence; finding_type = $finding.type }
            }
            'abnormal_uptime_signal' { [PSCustomObject]@{ id = 'monitor_uptime_context'; kind = 'monitor'; target = 'uptime'; reason = 'Track whether current signals change as uptime normalizes'; related_finding_ids = @($finding.id); severity = $finding.severity; confidence = $finding.confidence; finding_type = $finding.type } }
        }
    }

    $actions = @($actionTemplates | Sort-Object @{ Expression = { -$severityRank[$_.severity] } }, @{ Expression = { -[double]$_.confidence } }, @{ Expression = { -$actionabilityRank[$_.finding_type] } }, @{ Expression = { [string]$_.id } } | Select-Object -First 5 | ForEach-Object -Begin { $priority = 1 } -Process { [PSCustomObject]@{ id = $_.id; priority = $priority; kind = $_.kind; target = $_.target; reason = $_.reason; related_finding_ids = $_.related_finding_ids }; $priority++ })

    $score = 0
    foreach ($finding in $sortedFindings) { switch ($finding.severity) { 'warning' { $score += 20 }; 'critical' { $score += 40 } } }
    $score = [math]::Min($score, 100)

    $status = 'ok'
    if (@($sortedFindings | Where-Object severity -eq 'critical').Count -gt 0) { $status = 'critical' } elseif (@($sortedFindings | Where-Object severity -eq 'warning').Count -gt 0) { $status = 'warning' } elseif (@($sortedFindings | Where-Object severity -eq 'info').Count -gt 0) { $status = 'info' }

    $headline = if ($sortedFindings.Count -eq 0) { 'No abnormal system-health signals were identified in the last 60 minutes' } elseif ($sortedFindings.Count -eq 1) { [string]$sortedFindings[0].title } else { "$($sortedFindings[0].title) and $($sortedFindings[1].title)" }
    if ($headline.Length -gt 120) { $headline = $headline.Substring(0, 120).Trim() }

    $document = [PSCustomObject]@{
        schema_version = '1.0'
        kind = 'system_triage'
        host = [string]($NormalizedInput.host ?? $env:COMPUTERNAME)
        captured_at = [string]($NormalizedInput.captured_at ?? ([datetimeoffset]::Now.ToString('o')))
        window_minutes = 60
        summary = [PSCustomObject]@{ status = $status; score = $score; headline = $headline }
        findings = @($sortedFindings)
        actions = @($actions)
        sources = @($allSources | Select-Object -First 12)
    }

    $validation = Test-SystemTriageDocument -Document $document
    if (-not $validation.IsValid) { throw "System triage document validation failed: $($validation.Errors -join '; ')" }
    $document
}

function Test-SystemTriageDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Document,

        [string]$SchemaPath = (Join-Path $PSScriptRoot '..\docs\system-triage-v1.schema.json')
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $SchemaPath)) {
        $errors.Add("Schema file not found: $SchemaPath") | Out-Null
    } else {
        $json = $Document | ConvertTo-Json -Depth 10
        try {
            if (-not (Test-Json -Json $json -SchemaFile $SchemaPath -ErrorAction Stop)) { $errors.Add('Document failed JSON schema validation') | Out-Null }
        } catch {
            $errors.Add("Schema validation failed to run: $_") | Out-Null
        }
    }

    $findingIds = @($Document.findings | ForEach-Object { [string]$_.id })
    $sourceIds = @($Document.sources | ForEach-Object { [string]$_.id })
    $severityRank = @{ critical = 3; warning = 2; info = 1 }
    $actionabilityRank = @{ low_disk = 6; unstable_service = 5; high_memory = 4; high_cpu = 3; repeated_system_errors = 2; abnormal_uptime_signal = 1 }
    $allowedSourceScopes = @{
        'src_system' = @{ tool = 'Get-SystemSummary'; scope = 'local_host' }
        'src_processes' = @{ tool = 'Get-TopProcesses'; scope = 'top_processes' }
        'src_services' = @{ tool = 'Get-ServiceStatus'; scope = 'important_services' }
        'src_events' = @{ tool = 'Get-EventLogEntries'; scope = 'last_60_minutes' }
        'src_storage' = @{ tool = 'Get-StorageStatus'; scope = 'fixed_volumes' }
    }

    $dupFindingIds = @($findingIds | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
    if ($dupFindingIds.Count -gt 0) { $errors.Add("Duplicate finding ids: $($dupFindingIds -join ', ')") | Out-Null }
    $dupPriorities = @(@($Document.actions | ForEach-Object { [int]$_.priority }) | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
    if ($dupPriorities.Count -gt 0) { $errors.Add("Duplicate action priorities: $($dupPriorities -join ', ')") | Out-Null }
    foreach ($finding in @($Document.findings)) { foreach ($sourceRef in @($finding.source_refs)) { if ($sourceRef -notin $sourceIds) { $errors.Add("Finding source ref does not resolve: $sourceRef") | Out-Null } } }
    foreach ($action in @($Document.actions)) { foreach ($findingId in @($action.related_finding_ids)) { if ($findingId -notin $findingIds) { $errors.Add("Action related finding id does not resolve: $findingId") | Out-Null } } }

    $expectedFindingIdsInOrder = @(
        @($Document.findings) |
            Sort-Object @{ Expression = { -$severityRank[[string]$_.severity] } }, @{ Expression = { -[double]$_.confidence } }, @{ Expression = { -$actionabilityRank[[string]$_.type] } }, @{ Expression = { [string]$_.id } } |
            ForEach-Object { [string]$_.id }
    )
    if ((@($Document.findings | ForEach-Object { [string]$_.id }) -join '|') -ne ($expectedFindingIdsInOrder -join '|')) {
        $errors.Add('Findings are not sorted in deterministic v1 order') | Out-Null
    }

    $expectedActionIdsInOrder = @(
        @($Document.actions) |
            Sort-Object @{ Expression = { [int]$_.priority } }, @{ Expression = { [string]$_.id } } |
            ForEach-Object { [string]$_.id }
    )
    if ((@($Document.actions | ForEach-Object { [string]$_.id }) -join '|') -ne ($expectedActionIdsInOrder -join '|')) {
        $errors.Add('Actions are not sorted by ascending priority') | Out-Null
    }

    $expectedPriorities = if (@($Document.actions).Count -gt 0) { @(1..@($Document.actions).Count) } else { @() }
    $actualPriorities = @($Document.actions | ForEach-Object { [int]$_.priority })
    if (($actualPriorities -join '|') -ne ($expectedPriorities -join '|')) {
        $errors.Add('Action priorities must be contiguous starting at 1') | Out-Null
    }

    foreach ($source in @($Document.sources)) {
        $sourceId = [string]$source.id
        if ($allowedSourceScopes.ContainsKey($sourceId)) {
            $expected = $allowedSourceScopes[$sourceId]
            if ([string]$source.tool -ne [string]$expected.tool) {
                $errors.Add("Source tool mismatch for $sourceId") | Out-Null
            }
            if ([string]$source.scope -ne [string]$expected.scope) {
                $errors.Add("Source scope mismatch for $sourceId") | Out-Null
            }
        }
    }

    foreach ($finding in @($Document.findings)) {
        $findingType = [string]$finding.type
        $findingId = [string]$finding.id
        $findingCategory = [string]$finding.category

        switch ($findingType) {
            'high_cpu' {
                if ($findingCategory -ne 'cpu') { $errors.Add("high_cpu category mismatch: $findingId") | Out-Null }
                if ($findingId -ne 'high_cpu:global') { $errors.Add("high_cpu id mismatch: $findingId") | Out-Null }
            }
            'high_memory' {
                if ($findingCategory -ne 'memory') { $errors.Add("high_memory category mismatch: $findingId") | Out-Null }
                if ($findingId -ne 'high_memory:global') { $errors.Add("high_memory id mismatch: $findingId") | Out-Null }
            }
            'low_disk' {
                if ($findingCategory -ne 'disk') { $errors.Add("low_disk category mismatch: $findingId") | Out-Null }
                if ($findingId -notmatch '^low_disk:[a-z0-9_-]+$') { $errors.Add("low_disk id format mismatch: $findingId") | Out-Null }
            }
            'unstable_service' {
                if ($findingCategory -ne 'service') { $errors.Add("unstable_service category mismatch: $findingId") | Out-Null }
                if ($findingId -notmatch '^unstable_service:[a-z0-9_-]+$') { $errors.Add("unstable_service id format mismatch: $findingId") | Out-Null }
            }
            'repeated_system_errors' {
                if ($findingCategory -ne 'eventlog') { $errors.Add("repeated_system_errors category mismatch: $findingId") | Out-Null }
                if ($findingId -notmatch '^repeated_system_errors:[a-z0-9_-]+$') { $errors.Add("repeated_system_errors id format mismatch: $findingId") | Out-Null }
            }
            'abnormal_uptime_signal' {
                if ($findingCategory -ne 'uptime') { $errors.Add("abnormal_uptime_signal category mismatch: $findingId") | Out-Null }
                if ($findingId -ne 'abnormal_uptime_signal:global') { $errors.Add("abnormal_uptime_signal id mismatch: $findingId") | Out-Null }
            }
        }
    }

    $expectedStatus = 'ok'
    if (@($Document.findings | Where-Object severity -eq 'critical').Count -gt 0) { $expectedStatus = 'critical' } elseif (@($Document.findings | Where-Object severity -eq 'warning').Count -gt 0) { $expectedStatus = 'warning' } elseif (@($Document.findings | Where-Object severity -eq 'info').Count -gt 0) { $expectedStatus = 'info' }
    if ([string]$Document.summary.status -ne $expectedStatus) { $errors.Add("Summary status mismatch: expected $expectedStatus but found $($Document.summary.status)") | Out-Null }

    $expectedScore = 0
    foreach ($finding in @($Document.findings)) { switch ($finding.severity) { 'warning' { $expectedScore += 20 }; 'critical' { $expectedScore += 40 } } }
    $expectedScore = [math]::Min($expectedScore, 100)
    if ([int]$Document.summary.score -ne $expectedScore) { $errors.Add("Summary score mismatch: expected $expectedScore but found $($Document.summary.score)") | Out-Null }
    if ([int]$Document.window_minutes -ne 60) { $errors.Add('window_minutes must equal 60') | Out-Null }
    if (@($Document.findings | Where-Object type -eq 'low_disk').Count -gt 1) { $errors.Add('More than one low_disk finding was emitted') | Out-Null }
    if (@($Document.findings | Where-Object type -eq 'repeated_system_errors').Count -gt 1) { $errors.Add('More than one repeated_system_errors finding was emitted') | Out-Null }
    if (@($Document.findings | Where-Object type -eq 'abnormal_uptime_signal').Count -gt 1) { $errors.Add('More than one abnormal_uptime_signal finding was emitted') | Out-Null }
    if (@($Document.findings | Where-Object type -eq 'abnormal_uptime_signal').Count -gt 0 -and @($Document.findings).Count -lt 2) {
        $errors.Add('abnormal_uptime_signal must not appear without another finding') | Out-Null
    }

    [PSCustomObject]@{ IsValid = ($errors.Count -eq 0); Errors = @($errors) }
}
