# tools/Get-NetworkUsage.ps1
<#
.CLAW_NAME
    Get-NetworkUsage
.CLAW_DESCRIPTION
    Measures network bandwidth over a sampling interval by diffing adapter statistics before and after. Also shows which processes currently have established TCP connections. Note: Windows does not expose per-process byte counts natively — adapter usage reflects all processes combined.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    Network
#>
function Get-NetworkUsage {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 30)]
        [int]$Seconds = 5,

        # Filter the connections list to a specific process name (partial match).
        # Does not affect adapter-level byte measurement.
        [string]$ProcessName = ""
    )

    # Snapshot 1 — capture adapter byte counters before the interval
    $before = Get-NetAdapterStatistics |
        Where-Object { ($_.ReceivedBytes + $_.SentBytes) -gt 0 }

    Start-Sleep -Seconds $Seconds

    # Snapshot 2
    $after = Get-NetAdapterStatistics

    # Compute per-adapter deltas
    $adapterUsage = foreach ($b in $before) {
        $a = $after | Where-Object { $_.Name -eq $b.Name }
        if (-not $a) { continue }
        $rxBytes = $a.ReceivedBytes - $b.ReceivedBytes
        $txBytes = $a.SentBytes    - $b.SentBytes
        [PSCustomObject]@{
            Adapter    = $b.Name
            RxBytes    = $rxBytes
            TxBytes    = $txBytes
            TotalBytes = $rxBytes + $txBytes
            RxKBps     = [math]::Round($rxBytes / 1KB / $Seconds, 1)
            TxKBps     = [math]::Round($txBytes / 1KB / $Seconds, 1)
        }
    }

    # Active established TCP connections grouped by process (snapshot, no byte counts)
    $connections = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        ForEach-Object {
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                Process    = if ($proc) { $proc.Name } else { "PID $($_.OwningProcess)" }
                RemoteAddr = $_.RemoteAddress
                RemotePort = $_.RemotePort
            }
        } |
        Where-Object { -not $ProcessName -or $_.Process -like "*$ProcessName*" } |
        Group-Object Process |
        ForEach-Object {
            [PSCustomObject]@{
                Process     = $_.Name
                Connections = $_.Count
                RemoteHosts = ($_.Group.RemoteAddr | Sort-Object -Unique) -join ", "
            }
        }

    [PSCustomObject]@{
        SampledSeconds    = $Seconds
        AdapterUsage      = $adapterUsage
        ActiveConnections = $connections
        PerProcessNote    = "Adapter bytes = all processes combined. Per-process network byte counts require ETW and are not available here."
    }
}
