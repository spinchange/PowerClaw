# tools/Get-DirectoryListing.ps1
<#
.CLAW_NAME
    Get-DirectoryListing
.CLAW_DESCRIPTION
    Lists files and folders in a directory, with optional filtering.
.CLAW_RISK
    ReadOnly
#>
function Get-DirectoryListing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Filter = "*",

        [ValidateRange(1, 100)]
        [int]$Limit = 25
    )
    # Expand $env:VAR style references Claude may pass as literal strings
    $Path = [System.Environment]::ExpandEnvironmentVariables($Path) -replace '\$env:(\w+)', { [System.Environment]::GetEnvironmentVariable($_.Groups[1].Value) }
    Get-ChildItem -Path $Path -Filter $Filter -ErrorAction Stop |
        Select-Object -First $Limit -Property Name, Length, LastWriteTime, PSIsContainer
}
