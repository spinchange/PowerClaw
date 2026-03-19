# tools/Get-EventLogEntries.ps1
<#
.CLAW_NAME
    Get-EventLogEntries
.CLAW_DESCRIPTION
    Queries Windows Event Logs for errors, warnings, or informational events. Use this to diagnose crashes, service failures, system errors, or anything unusual that happened on the machine. Defaults to errors and warnings from the last 24 hours.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    SystemInfo
#>
function Get-EventLogEntries {
    [CmdletBinding()]
    param(
        [ValidateSet("System", "Application", "Security", "Setup")]
        [string]$LogName = "System",

        [ValidateSet("Error", "Warning", "Information", "Critical", "All")]
        [string]$Level = "Error",

        [ValidateRange(1, 168)]
        [int]$HoursBack = 24,

        [ValidateRange(1, 100)]
        [int]$Limit = 25
    )

    $after = (Get-Date).AddHours(-$HoursBack)

    $levelMap = @{
        Critical    = 1
        Error       = 2
        Warning     = 3
        Information = 4
    }

    $filter = @{
        LogName   = $LogName
        StartTime = $after
    }

    if ($Level -ne "All") {
        # Include Critical when Error is requested — both indicate failures
        if ($Level -eq "Error") {
            $filter.Level = @(1, 2)
        } else {
            $filter.Level = $levelMap[$Level]
        }
    }

    try {
        $events = Get-WinEvent -FilterHashtable $filter -ErrorAction Stop |
            Select-Object -First $Limit
    }
    catch [System.Exception] {
        if ($_.Exception.Message -match "No events were found") {
            return [PSCustomObject]@{
                LogName  = $LogName
                Level    = $Level
                HoursBack = $HoursBack
                Count    = 0
                Message  = "No matching events found in the last $HoursBack hours."
            }
        }
        throw "Event log query failed: $_"
    }

    $events | ForEach-Object {
        [PSCustomObject]@{
            TimeCreated = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            Level       = $_.LevelDisplayName
            Source      = $_.ProviderName
            EventId     = $_.Id
            Message     = ($_.Message -split "`n")[0].Trim()  # first line only — full messages are huge
        }
    }
}
