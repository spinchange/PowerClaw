# tools/Get-ServiceStatus.ps1
<#
.CLAW_NAME
    Get-ServiceStatus
.CLAW_DESCRIPTION
    Returns the status of Windows services. Use this to check if a specific service is running, find services that have stopped unexpectedly, or list all running or failed services. Good for diagnosing crashes like a stopped search service or failed background task.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    SystemInfo
#>
function Get-ServiceStatus {
    [CmdletBinding()]
    param(
        [string]$Name,

        [ValidateSet("All", "Running", "Stopped", "Failed")]
        [string]$Filter = "All",

        [ValidateSet("Auto", "Manual", "Disabled", "Any")]
        [string]$StartType = "Any",

        [ValidateRange(1, 200)]
        [int]$Limit = 50
    )

    $services = Get-Service -ErrorAction SilentlyContinue

    if ($Name) {
        $services = $services | Where-Object { $_.Name -like "*$Name*" -or $_.DisplayName -like "*$Name*" }
    }

    # Filter by status
    $services = switch ($Filter) {
        "Running" { $services | Where-Object { $_.Status -eq "Running" } }
        "Stopped" { $services | Where-Object { $_.Status -eq "Stopped" } }
        "Failed"  {
            # Stopped services with AutoStart = stopped unexpectedly
            $services | Where-Object {
                $_.Status -eq "Stopped" -and $_.StartType -eq "Automatic"
            }
        }
        default   { $services }
    }

    # Filter by start type
    if ($StartType -ne "Any") {
        $services = $services | Where-Object { $_.StartType -eq $StartType }
    }

    $services | Select-Object -First $Limit | ForEach-Object {
        [PSCustomObject]@{
            Name        = $_.Name
            DisplayName = $_.DisplayName
            Status      = $_.Status.ToString()
            StartType   = $_.StartType.ToString()
        }
    }
}
