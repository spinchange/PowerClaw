<#
.CLAW_NAME
    Get-PowerSettings
.CLAW_DESCRIPTION
    Reads the current Windows power, display timeout, sleep, hibernate, and basic lock-related idle settings for the active user and active power scheme.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    SystemInfo
#>
function Get-PowerSettings {
    [CmdletBinding()]
    param()

    function Get-ValueFromQuery {
        param(
            [string]$Output,
            [ValidateSet('AC', 'DC')]
            [string]$Mode
        )

        if ([string]::IsNullOrWhiteSpace($Output)) {
            return $null
        }

        $pattern = if ($Mode -eq 'AC') {
            'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)'
        } else {
            'Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)'
        }

        $match = [regex]::Match($Output, $pattern)
        if (-not $match.Success) {
            return $null
        }

        return [Convert]::ToInt32($match.Groups[1].Value, 16)
    }

    $activeSchemeOutput = & powercfg /getactivescheme 2>$null
    $activeSchemeName = $null
    $activeSchemeGuid = $null
    if ($activeSchemeOutput -match 'Power Scheme GUID:\s*([a-fA-F0-9-]+)\s*\((.+)\)') {
        $activeSchemeGuid = $Matches[1]
        $activeSchemeName = $Matches[2].Trim()
    }

    $videoIdleOutput = (& powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 2>$null) -join "`n"
    $sleepIdleOutput = (& powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>$null) -join "`n"
    $hibernateIdleOutput = (& powercfg /query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 2>$null) -join "`n"

    $screenSaver = Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue
    $systemPolicies = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue

    $displayAcSeconds = Get-ValueFromQuery -Output $videoIdleOutput -Mode AC
    $displayDcSeconds = Get-ValueFromQuery -Output $videoIdleOutput -Mode DC
    $sleepAcSeconds = Get-ValueFromQuery -Output $sleepIdleOutput -Mode AC
    $sleepDcSeconds = Get-ValueFromQuery -Output $sleepIdleOutput -Mode DC
    $hibernateAcSeconds = Get-ValueFromQuery -Output $hibernateIdleOutput -Mode AC
    $hibernateDcSeconds = Get-ValueFromQuery -Output $hibernateIdleOutput -Mode DC

    $displaySummary = if ($null -ne $displayAcSeconds -or $null -ne $displayDcSeconds) {
        "Display timeout is $([math]::Round(($displayAcSeconds ?? 0) / 60, 1)) minute(s) on AC and $([math]::Round(($displayDcSeconds ?? 0) / 60, 1)) minute(s) on battery."
    } else {
        'Display timeout settings were not available from powercfg.'
    }

    $sleepSummary = if ($null -ne $sleepAcSeconds -or $null -ne $sleepDcSeconds) {
        "Sleep timeout is $([math]::Round(($sleepAcSeconds ?? 0) / 60, 1)) minute(s) on AC and $([math]::Round(($sleepDcSeconds ?? 0) / 60, 1)) minute(s) on battery."
    } else {
        'Sleep timeout settings were not available from powercfg.'
    }

    [PSCustomObject]@{
        kind = 'power_settings'
        captured_at = [datetimeoffset]::Now.ToString('o')
        active_scheme = [PSCustomObject]@{
            name = $activeSchemeName
            guid = $activeSchemeGuid
        }
        display = [PSCustomObject]@{
            timeout_ac_seconds = $displayAcSeconds
            timeout_dc_seconds = $displayDcSeconds
        }
        sleep = [PSCustomObject]@{
            timeout_ac_seconds = $sleepAcSeconds
            timeout_dc_seconds = $sleepDcSeconds
            hibernate_ac_seconds = $hibernateAcSeconds
            hibernate_dc_seconds = $hibernateDcSeconds
        }
        lock = [PSCustomObject]@{
            screen_saver_enabled = if ($null -ne $screenSaver.ScreenSaveActive) { [string]$screenSaver.ScreenSaveActive } else { $null }
            screen_saver_timeout_seconds = if ($null -ne $screenSaver.ScreenSaveTimeOut) { [int]$screenSaver.ScreenSaveTimeOut } else { $null }
            screen_saver_secure_on_resume = if ($null -ne $screenSaver.ScreenSaverIsSecure) { [string]$screenSaver.ScreenSaverIsSecure } else { $null }
            machine_inactivity_timeout_seconds = if ($null -ne $systemPolicies.InactivityTimeoutSecs) { [int]$systemPolicies.InactivityTimeoutSecs } else { $null }
        }
        summary = [PSCustomObject]@{
            headline = $displaySummary
            sleep = $sleepSummary
            lock = if ($null -ne $systemPolicies.InactivityTimeoutSecs) {
                "Machine inactivity timeout before lock is $($systemPolicies.InactivityTimeoutSecs) second(s)."
            } else {
                'No machine inactivity lock timeout policy was detected.'
            }
        }
    }
}
