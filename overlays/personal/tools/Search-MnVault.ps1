# overlays/personal/tools/Search-MnVault.ps1
<#
.CLAW_NAME
    Search-MnVault
.CLAW_DESCRIPTION
    Searches markdown notes in the mnvault knowledge base by keyword, tag, or subdirectory. Available subdirectories: agents, daily, minimal-notes, scripts, tools. Use StatsOnly=true to get file count and total size without searching. Use this to find notes, decisions, session summaries, or reference material.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    Personal
#>
function Search-MnVault {
    [CmdletBinding()]
    param(
        [string]$Query,

        [ValidateSet("agents", "daily", "minimal-notes", "scripts", "tools", "all")]
        [string]$Section = "all",

        [string]$Tag,

        [ValidateRange(1, 50)]
        [int]$Limit = 20,

        [ValidateRange(1, 10)]
        [int]$ContextLines = 3,

        [bool]$StatsOnly = $false
    )

    $vaultRoot = "G:\My Drive\mnvault"
    if (-not (Test-Path $vaultRoot)) {
        throw "mnvault not found at $vaultRoot — is Google Drive mounted?"
    }

    $searchPath = if ($Section -eq "all") { $vaultRoot } else { Join-Path $vaultRoot $Section }
    if (-not (Test-Path $searchPath)) {
        throw "Section '$Section' not found in vault."
    }

    $files = Get-ChildItem -Path $searchPath -Filter "*.md" -Recurse -ErrorAction SilentlyContinue

    # ── Stats mode ──
    if ($StatsOnly) {
        $totalLines = ($files | ForEach-Object { (Get-Content $_.FullName -ErrorAction SilentlyContinue | Measure-Object).Count }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
        $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
        return [PSCustomObject]@{
            FileCount   = $files.Count
            TotalLines  = $totalLines
            TotalSizeMB = [math]::Round($totalBytes / 1MB, 2)
            SearchPath  = $searchPath
        }
    }

    # Escape regex special chars so Claude can pass plain keywords
    $escapedQuery = if ($Query) { [regex]::Escape($Query) } else { $null }
    $escapedTag   = if ($Tag)   { [regex]::Escape("#$($Tag.TrimStart('#'))") } else { $null }

    $searchTerm = if ($escapedTag -and $escapedQuery) { "$escapedTag.*$escapedQuery|$escapedQuery.*$escapedTag" }
                  elseif ($escapedTag)                { $escapedTag }
                  elseif ($escapedQuery)              { $escapedQuery }
                  else { throw "Provide at least one of: -Query, -Tag, or -StatsOnly true" }

    $results = @()

    foreach ($file in $files) {
        $matches = Select-String -Path $file.FullName -Pattern $searchTerm -Context $ContextLines -CaseSensitive:$false -ErrorAction SilentlyContinue

        foreach ($match in $matches) {
            # Resolve section from path
            $relativePath = $file.FullName.Replace($vaultRoot, "").TrimStart('\')

            $results += [PSCustomObject]@{
                File        = $file.BaseName
                Path        = $relativePath
                Line        = $match.LineNumber
                Match       = $match.Line.Trim()
                Context     = ($match.Context.PreContext + @($match.Line) + $match.Context.PostContext) -join "`n"
                LastWritten = $file.LastWriteTime.ToString("yyyy-MM-dd")
            }
            if ($results.Count -ge $Limit) { break }
        }
        if ($results.Count -ge $Limit) { break }
    }

    if ($results.Count -eq 0) {
        return [PSCustomObject]@{ Message = "No matches found for '$searchTerm' in $searchPath." }
    }

    $results
}
