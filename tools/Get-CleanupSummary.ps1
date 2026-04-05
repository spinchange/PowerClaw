<#
.CLAW_NAME
    Get-CleanupSummary
.CLAW_DESCRIPTION
    Produces a deterministic cleanup_summary document for a bounded scope by discovering large files and reducing them into ranked cleanup candidates, explicit candidate states, and a next safe action. Use this first for cleanup, biggest-file, and "what can I delete" prompts.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    Filesystem
#>
function Get-CleanupSummary {
    [CmdletBinding()]
    param(
        [string]$Scope = "$env:USERPROFILE\Downloads",

        [ValidateRange(1, 25)]
        [int]$Limit = 10,

        [ValidateRange(0, 500000)]
        [int]$MinSizeMB = 50,

        [switch]$AsJson
    )

    Invoke-CleanupSummary -Scope $Scope -Limit $Limit -MinSizeMB $MinSizeMB -AsJson:$AsJson
}
