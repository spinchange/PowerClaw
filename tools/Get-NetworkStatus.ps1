# tools/Get-NetworkStatus.ps1
<#
.CLAW_NAME
    Get-NetworkStatus
.CLAW_DESCRIPTION
    Returns a summary of network interfaces, active connections, DNS servers, and external IP. Use this to diagnose connectivity issues, see what's connected, or check network configuration.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    Network
#>
function Get-NetworkStatus {
    [CmdletBinding()]
    param(
        [ValidateSet("Summary", "Interfaces", "Connections", "Full")]
        [string]$View = "Summary"
    )

    $result = [PSCustomObject]@{}

    # ── Active interfaces ──
    $interfaces = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ip = Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Name       = $_.Name
            Type       = $_.MediaType
            Speed      = if ($_.LinkSpeed -is [string]) { $_.LinkSpeed } elseif ($_.LinkSpeed) { "$([math]::Round([double]$_.LinkSpeed / 1MB, 0)) Mbps" } else { "Unknown" }
            MacAddress = $_.MacAddress
            IPAddress  = $ip.IPAddress
        }
    }

    # ── DNS servers ──
    $dns = Get-DnsClientServerAddress -AddressFamily IPv4 |
        Where-Object { $_.ServerAddresses.Count -gt 0 } |
        Select-Object -First 2 -ExpandProperty ServerAddresses

    # ── Active TCP connections (established only) ──
    $connections = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        ForEach-Object {
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                LocalPort  = $_.LocalPort
                RemoteAddr = $_.RemoteAddress
                RemotePort = $_.RemotePort
                Process    = $proc.Name
                PID        = $_.OwningProcess
            }
        } | Sort-Object Process | Select-Object -First 20

    # ── External IP (best effort) ──
    $externalIp = $null
    if ($View -in @("Summary", "Full")) {
        try {
            $externalIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5)
        } catch {
            $externalIp = "Unavailable"
        }
    }

    switch ($View) {
        "Interfaces"  { $interfaces }
        "Connections" { $connections }
        "Summary" {
            [PSCustomObject]@{
                ActiveInterfaces    = $interfaces
                DNSServers          = $dns
                ExternalIP          = $externalIp
                EstablishedConCount = ($connections | Measure-Object).Count
            }
        }
        "Full" {
            [PSCustomObject]@{
                ActiveInterfaces = $interfaces
                DNSServers       = $dns
                ExternalIP       = $externalIp
                Connections      = $connections
            }
        }
    }
}
