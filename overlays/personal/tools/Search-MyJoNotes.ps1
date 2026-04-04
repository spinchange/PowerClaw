# overlays/personal/tools/Search-MyJoNotes.ps1
<#
.CLAW_NAME
    Search-MyJoNotes
.CLAW_DESCRIPTION
    Searches journal entries across MyJo notebooks by keyword, tag, notebook name, or date range. Returns matching entries with context. Use StatsOnly=true to get file count and total size without searching. Available notebooks: default, devlog, trading, watchlist, personal, projects, research, health, learning, work, commonplace, ai-chats, gemini.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    Personal
#>
function Search-MyJoNotes {
    [CmdletBinding()]
    param(
        [string]$Query,

        [string]$Notebook = "",

        [string]$Tag,

        [datetime]$After,

        [datetime]$Before,

        [ValidateRange(1, 50)]
        [int]$Limit = 20,

        [ValidateRange(1, 10)]
        [int]$ContextLines = 2,

        [bool]$StatsOnly = $false
    )

    # ── Parse notebook paths from config ──
    $configPath = Join-Path $env:USERPROFILE ".myjo\config.txt"
    if (-not (Test-Path $configPath)) {
        throw "MyJo config not found at $configPath"
    }

    $config = Get-Content $configPath
    $notebookMap = @{}
    foreach ($line in $config) {
        if ($line -match '^notebook:(.+)=(.+)$') {
            $notebookMap[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    # Determine which notebooks to search
    $searchPaths = if ($Notebook) {
        if (-not $notebookMap.ContainsKey($Notebook)) {
            throw "Unknown notebook '$Notebook'. Available: $($notebookMap.Keys -join ', ')"
        }
        @($notebookMap[$Notebook])
    } else {
        $notebookMap.Values
    }

    $results = @()
    $skippedEncrypted = 0

    # ── Stats mode ──
    if ($StatsOnly) {
        $allFiles = $searchPaths | ForEach-Object {
            if (Test-Path $_) { Get-ChildItem -Path $_ -Filter "*.txt" -Recurse -ErrorAction SilentlyContinue }
        }
        $totalBytes = ($allFiles | Measure-Object -Property Length -Sum).Sum
        return [PSCustomObject]@{
            FileCount   = $allFiles.Count
            TotalSizeMB = [math]::Round($totalBytes / 1MB, 2)
            Notebooks   = $notebookMap.Keys -join ", "
        }
    }

    # Escape regex special chars so Claude can pass plain keywords safely
    $escapedQuery = if ($Query) { [regex]::Escape($Query) } else { $null }
    $escapedTag   = if ($Tag)   { [regex]::Escape("#$($Tag.TrimStart('#'))") } else { $null }

    $searchTerm = if ($escapedTag -and $escapedQuery) { "$escapedTag.*$escapedQuery|$escapedQuery.*$escapedTag" }
                  elseif ($escapedTag)                { $escapedTag }
                  elseif ($escapedQuery)              { $escapedQuery }
                  else { throw "Provide at least one of: -Query, -Tag, or -StatsOnly true" }

    foreach ($path in $searchPaths) {
        if (-not (Test-Path $path)) { continue }

        $files = Get-ChildItem -Path $path -Filter "*.txt" -Recurse -ErrorAction SilentlyContinue

        # Date range filter on file modified time (fast pre-filter)
        if ($After)  { $files = $files | Where-Object { $_.LastWriteTime -ge $After } }
        if ($Before) { $files = $files | Where-Object { $_.LastWriteTime -le $Before } }

        foreach ($file in $files) {
            # Detect encrypted / binary content
            try {
                $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                $nullCount = ($bytes | Where-Object { $_ -eq 0 }).Count
                if ($nullCount -gt ($bytes.Count * 0.02)) {
                    $skippedEncrypted++
                    continue
                }
            } catch { continue }

            # Resolve notebook name from path
            $notebookName = ($notebookMap.GetEnumerator() |
                Where-Object { $file.FullName.StartsWith($_.Value) } |
                Select-Object -First 1).Key

            $matches = Select-String -Path $file.FullName -Pattern $searchTerm -Context $ContextLines -ErrorAction SilentlyContinue

            foreach ($match in $matches) {
                $results += [PSCustomObject]@{
                    Notebook    = $notebookName
                    File        = $file.Name
                    Line        = $match.LineNumber
                    Match       = $match.Line.Trim()
                    Context     = ($match.Context.PreContext + @($match.Line) + $match.Context.PostContext) -join "`n"
                    LastWritten = $file.LastWriteTime.ToString("yyyy-MM-dd")
                }
                if ($results.Count -ge $Limit) { break }
            }
            if ($results.Count -ge $Limit) { break }
        }
        if ($results.Count -ge $Limit) { break }
    }

    if ($skippedEncrypted -gt 0) {
        Write-Warning "$skippedEncrypted encrypted file(s) skipped — set encryption=disabled in ~/.myjo/config.txt to make them searchable."
    }

    if ($results.Count -eq 0) {
        return [PSCustomObject]@{ Message = "No matches found for '$searchTerm'." }
    }

    $results
}
