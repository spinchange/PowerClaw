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
    $pwBuild = Get-ChildItem (Join-Path $env:USERPROFILE ".powerclaw-playwright\PwHost\PwHost\bin\Debug") -Directory |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not (Test-Path $pwBuild)) {
        throw "Playwright not set up. Run the one-time setup in the PowerCLAW README."
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

    try {
        $playwright = Await ([Microsoft.Playwright.Playwright]::CreateAsync())

        # Use installed Chrome if available — real Chrome is far less likely to be flagged
        # Falls back to bundled Chromium if Chrome isn't installed
        $launchOptions = [Microsoft.Playwright.BrowserTypeLaunchOptions]@{
            Headless = $true
            Channel  = "chrome"
            Args     = [string[]]@(
                "--disable-blink-features=AutomationControlled"
                "--no-sandbox"
            )
        }
        try {
            $browser = Await ($playwright.Chromium.LaunchAsync($launchOptions))
        }
        catch {
            # Chrome not installed — fall back to bundled Chromium
            $launchOptions.Channel = $null
            $browser = Await ($playwright.Chromium.LaunchAsync($launchOptions))
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
        throw "Fetch-WebPage failed for '$Url': $_"
    }
    finally {
        if ($context)    { try { Await ($context.CloseAsync())  } catch {} }
        if ($browser)    { try { Await ($browser.CloseAsync())  } catch {} }
        if ($playwright) { try { $playwright.Dispose()          } catch {} }
    }
}
