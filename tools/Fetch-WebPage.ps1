# tools/Fetch-WebPage.ps1
<#
.CLAW_NAME
    Fetch-WebPage
.CLAW_DESCRIPTION
    Fetches a web page and returns clean readable text. Handles JavaScript-rendered pages, single-page apps, and dynamic content. Use this for any URL — news articles, financial data sites, documentation, any page a human can read in a browser.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    Web
#>
function Get-ClawPlaywrightDebugRoot {
    $pwDebugRoot = [System.Environment]::GetEnvironmentVariable('POWERCLAW_PLAYWRIGHT_BUILD')
    if ([string]::IsNullOrWhiteSpace($pwDebugRoot)) {
        $pwDebugRoot = Join-Path $env:USERPROFILE ".powerclaw-playwright\PwHost\PwHost\bin\Debug"
    }

    return $pwDebugRoot
}

function Get-ClawBrowserLaunchCandidates {
    $candidates = @(
        @{ Label = 'Chrome channel'; Channel = 'chrome'; ExecutablePath = $null },
        @{ Label = 'Edge channel'; Channel = 'msedge'; ExecutablePath = $null }
    )

    $knownExecutables = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($executable in $knownExecutables | Select-Object -Unique) {
        $candidates += @{ Label = "Installed browser ($([System.IO.Path]::GetFileName($executable)))"; Channel = $null; ExecutablePath = $executable }
    }

    $candidates += @{ Label = 'Bundled Chromium'; Channel = $null; ExecutablePath = $null }
    return $candidates
}

function Resolve-ClawWebFetchFailureMessage {
    param(
        [string]$Url,
        [string]$FailureText,
        [string[]]$LaunchAttempts
    )

    $attemptText = if ($LaunchAttempts -and $LaunchAttempts.Count -gt 0) {
        " Launch attempts: $($LaunchAttempts -join ', ')."
    } else {
        ''
    }

    if ($FailureText -match 'spawn EPERM|Access is denied|access denied|not permitted') {
        return "Fetch-WebPage could not launch a browser for '$Url'. The Playwright runtime is installed, but this session appears to block headless browser launch.$attemptText Try running PowerClaw from a normal local PowerShell session outside constrained or sandboxed hosts."
    }

    if ($FailureText -match 'Executable doesn''t exist|executable doesn''t exist|Failed to launch.*browser') {
        return "Fetch-WebPage could not find a usable browser runtime for '$Url'.$attemptText Re-run `Install-PowerClawWebRuntime.ps1` to refresh the Playwright browser install, then run Test-PowerClawSetup to verify the web runtime path."
    }

    if ($FailureText -match 'Timeout|timed out') {
        return "Fetch-WebPage timed out while loading '$Url'. Try a larger TimeoutMs value or retry the request if the site is slow."
    }

    $summaryLine = ($FailureText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    return "Fetch-WebPage failed for '$Url'.$attemptText $summaryLine"
}

function Fetch-WebPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [ValidateSet("Load", "NetworkIdle", "DOMContentLoaded")]
        [string]$WaitUntil = "Load",

        [ValidateRange(500, 30000)]
        [int]$TimeoutMs = 15000,

        [ValidateRange(1000, 50000)]
        [int]$MaxChars = 8000
    )

    # ── Load Playwright DLLs ──
    $pwDebugRoot = Get-ClawPlaywrightDebugRoot
    $pwBuild = Get-ChildItem $pwDebugRoot -Directory |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not (Test-Path $pwBuild)) {
        throw "Playwright not set up. Run the one-time setup in the PowerClaw README."
    }

    $alreadyLoaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.Playwright' }

    if (-not $alreadyLoaded) {
        Get-ChildItem "$pwBuild\*.dll" | ForEach-Object {
            try { Add-Type -Path $_.FullName -ErrorAction Stop } catch {}
        }
    }

    # ── Await helper — PS7 has no ambient async context ──
    function Await($task) { $task.GetAwaiter().GetResult() }

    $playwright = $null
    $browser    = $null
    $context    = $null
    $launchAttempts = [System.Collections.Generic.List[string]]::new()

    try {
        $playwright = Await ([Microsoft.Playwright.Playwright]::CreateAsync())

        foreach ($candidate in Get-ClawBrowserLaunchCandidates) {
            $launchAttempts.Add($candidate.Label)
            $launchOptions = [Microsoft.Playwright.BrowserTypeLaunchOptions]@{
                Headless       = $true
                Channel        = $candidate.Channel
                ExecutablePath = $candidate.ExecutablePath
                Args           = [string[]]@(
                    "--disable-blink-features=AutomationControlled"
                    "--no-sandbox"
                )
            }

            try {
                $browser = Await ($playwright.Chromium.LaunchAsync($launchOptions))
                break
            }
            catch {
                $lastLaunchError = $_
            }
        }

        if (-not $browser) {
            throw $lastLaunchError
        }

        # Realistic browser context — viewport, locale, user agent
        $contextOptions = [Microsoft.Playwright.BrowserNewContextOptions]@{
            ViewportSize        = [Microsoft.Playwright.ViewportSize]@{ Width = 1280; Height = 800 }
            UserAgent           = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
            Locale              = "en-US"
            TimezoneId          = "America/New_York"
            JavaScriptEnabled   = $true
        }
        $context = Await ($browser.NewContextAsync($contextOptions))
        $page    = Await ($context.NewPageAsync())

        $gotoOptions = [Microsoft.Playwright.PageGotoOptions]@{
            Timeout   = $TimeoutMs
            WaitUntil = switch ($WaitUntil) {
                "Load"             { [Microsoft.Playwright.WaitUntilState]::Load }
                "NetworkIdle"      { [Microsoft.Playwright.WaitUntilState]::NetworkIdle }
                "DOMContentLoaded" { [Microsoft.Playwright.WaitUntilState]::DOMContentLoaded }
            }
        }

        Await ($page.GotoAsync($Url, $gotoOptions)) | Out-Null

        # innerText respects CSS visibility — skips hidden elements, scripts, styles
        $text  = Await ($page.Locator("body").InnerTextAsync())
        $title = Await ($page.TitleAsync())

        # Collapse excess whitespace
        $text = $text -replace "`r`n", "`n" -replace "`n{3,}", "`n`n" -replace " {2,}", " "
        $text = $text.Trim()

        $truncated = $text.Length -gt $MaxChars
        if ($truncated) {
            $text = $text.Substring(0, $MaxChars) + "`n... (truncated — $($text.Length) chars total)"
        }

        [PSCustomObject]@{
            Url        = $Url
            Title      = $title
            Characters = $text.Length
            Truncated  = $truncated
            Content    = $text
        }
    }
    catch {
        $failureText = "$_"
        throw (Resolve-ClawWebFetchFailureMessage -Url $Url -FailureText $failureText -LaunchAttempts @($launchAttempts))
    }
    finally {
        if ($context)    { try { Await ($context.CloseAsync())  } catch {} }
        if ($browser)    { try { Await ($browser.CloseAsync())  } catch {} }
        if ($playwright) { try { $playwright.Dispose()          } catch {} }
    }
}
