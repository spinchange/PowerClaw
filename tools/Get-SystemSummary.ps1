# tools/Get-SystemSummary.ps1
<#
.CLAW_NAME
    Get-SystemSummary
.CLAW_DESCRIPTION
    Returns a snapshot of system health — CPU usage, RAM, uptime, OS version, machine name, and top resource consumers. Use this for a quick machine health check or to understand current load.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    SystemInfo
#>
function Get-SystemSummary {
    [CmdletBinding()]
    param(
        [ValidateSet("Full", "Quick")]
        [string]$View = "Full"
    )

    # ── OS / Machine ──
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1

    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeStr = "{0}d {1}h {2}m" -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes

    $ramTotalGB  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $ramFreeGB   = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $ramUsedGB   = [math]::Round($ramTotalGB - $ramFreeGB, 1)
    $ramPct      = [math]::Round(($ramUsedGB / $ramTotalGB) * 100, 1)

    $summary = [PSCustomObject]@{
        MachineName   = $env:COMPUTERNAME
        OSVersion     = $os.Caption
        OSBuild       = $os.BuildNumber
        Uptime        = $uptimeStr
        LastBoot      = $os.LastBootUpTime.ToString("yyyy-MM-dd HH:mm")
        CPU           = $cpu.Name.Trim()
        CPUCores      = $cs.NumberOfLogicalProcessors
        CPULoadPct    = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        RAMTotalGB    = $ramTotalGB
        RAMUsedGB     = $ramUsedGB
        RAMFreeGB     = $ramFreeGB
        RAMUsedPct    = $ramPct
    }

    if ($View -eq "Quick") { return $summary }

    # ── Top processes by CPU and memory ──
    $topCpu = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 -Property Name, Id,
        @{ Name = 'CPUSeconds'; Expression = { [math]::Round($_.CPU, 1) } },
        @{ Name = 'MemoryMB';   Expression = { [math]::Round($_.WorkingSet64 / 1MB, 1) } }

    $topRam = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 -Property Name, Id,
        @{ Name = 'MemoryMB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 1) } }

    # ── Page file ──
    $pageFile = Get-CimInstance Win32_PageFileUsage | Select-Object -First 1
    $pageFileSummary = if ($pageFile) {
        [PSCustomObject]@{
            AllocatedMB = $pageFile.AllocatedBaseSize
            UsedMB      = $pageFile.CurrentUsage
            PeakMB      = $pageFile.PeakUsage
        }
    } else { $null }

    [PSCustomObject]@{
        System       = $summary
        TopByCPU     = $topCpu
        TopByMemory  = $topRam
        PageFile     = $pageFileSummary
    }
}
