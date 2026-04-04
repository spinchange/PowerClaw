# tools/Get-TopProcesses.ps1
<#
.CLAW_NAME
    Get-TopProcesses
.CLAW_DESCRIPTION
    Returns the top N processes sorted by CPU or Memory usage.
.CLAW_RISK
    ReadOnly
#>
function Get-TopProcesses {
    [CmdletBinding()]
    param(
        [ValidateSet("CPU", "Memory")]
        [string]$SortBy = "CPU",

        [ValidateRange(1, 50)]
        [int]$Count = 5
    )
    $sortProperty = switch ($SortBy) {
        'CPU'    { 'CPU' }
        'Memory' { 'WorkingSet64' }
    }

    Get-Process |
        Sort-Object $sortProperty -Descending |
        Select-Object -First $Count -Property Name, Id, CPU, @{
            Name = 'MemoryMB'
            Expression = { [math]::Round($_.WorkingSet64 / 1MB, 1) }
        }
}
