<#
.CLAW_NAME
    Get-RecentChangesSummary
.CLAW_DESCRIPTION
    Produces a deterministic bounded summary of recent file changes and recent system events for the requested scope and time window.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    SystemInfo
#>
function Get-RecentChangesSummary {
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

    Invoke-RecentChangesSummary `
        -Scope $Scope `
        -HoursBack $HoursBack `
        -Limit $Limit `
        -EventLimit $EventLimit `
        -AsJson:$AsJson
}
