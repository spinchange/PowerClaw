<#
.CLAW_NAME
    Get-SystemTriage
.CLAW_DESCRIPTION
    Produces a deterministic workstation health triage document by running the bounded system collectors and reducing them into a single system_triage result. Use this first for full health checks, diagnostics, and general machine-health summaries.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    SystemInfo
#>
function Get-SystemTriage {
    [CmdletBinding()]
    param(
        [switch]$AsJson
    )

    Invoke-SystemTriage -AsJson:$AsJson
}
