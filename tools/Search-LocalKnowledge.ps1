<#
.CLAW_NAME
    Search-LocalKnowledge
.CLAW_DESCRIPTION
    Searches local notes, docs, logs, and other evidence files in the configured knowledge roots, defaulting to Documents, and returns the most relevant matches.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    Filesystem
#>
function Search-LocalKnowledge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Query,

        [ValidateSet('all', 'documents')]
        [string]$Collection = 'all',

        [ValidateRange(1, 25)]
        [int]$Limit = 10
    )

    $roots = [System.Collections.Generic.List[string]]::new()
    $documentsRoot = [Environment]::GetFolderPath('MyDocuments')
    if (-not [string]::IsNullOrWhiteSpace($documentsRoot) -and (Test-Path -LiteralPath $documentsRoot)) {
        $roots.Add($documentsRoot) | Out-Null
    }

    if ($roots.Count -eq 0) {
        return @()
    }

    $patterns = @('*.md', '*.txt', '*.log', '*.json', '*.yml', '*.yaml', '*.xml', '*.ps1', '*.psm1', '*.psd1')
    $results = [System.Collections.Generic.List[object]]::new()

    $rg = Get-Command rg -ErrorAction SilentlyContinue
    if ($rg) {
        foreach ($root in $roots) {
            $rgResults = & $rg.Source --no-heading --line-number --color never --smart-case --glob '*.md' --glob '*.txt' --glob '*.log' --glob '*.json' --glob '*.yml' --glob '*.yaml' --glob '*.xml' --glob '*.ps1' --glob '*.psm1' --glob '*.psd1' -- $Query $root 2>$null
            foreach ($line in @($rgResults | Select-Object -First $Limit)) {
                if ($line -match '^(.*?):(\d+):(.*)$') {
                    $path = $Matches[1]
                    $lineNumber = [int]$Matches[2]
                    $snippet = $Matches[3].Trim()
                    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
                    $results.Add([PSCustomObject]@{
                        Collection   = 'documents'
                        Name         = if ($item) { $item.Name } else { [System.IO.Path]::GetFileName($path) }
                        Path         = $path
                        Line         = $lineNumber
                        Snippet      = $snippet
                        LastModified = if ($item) { $item.LastWriteTime } else { $null }
                    }) | Out-Null
                    if ($results.Count -ge $Limit) {
                        return @($results)
                    }
                }
            }
        }

        return @($results)
    }

    foreach ($root in $roots) {
        $files = Get-ChildItem -LiteralPath $root -Recurse -File -Include $patterns -ErrorAction SilentlyContinue
        foreach ($match in ($files | Select-String -Pattern $Query -SimpleMatch -CaseSensitive:$false -ErrorAction SilentlyContinue | Select-Object -First ($Limit - $results.Count))) {
            $results.Add([PSCustomObject]@{
                Collection   = 'documents'
                Name         = $match.Path | Split-Path -Leaf
                Path         = $match.Path
                Line         = $match.LineNumber
                Snippet      = $match.Line.Trim()
                LastModified = (Get-Item -LiteralPath $match.Path -ErrorAction SilentlyContinue).LastWriteTime
            }) | Out-Null
            if ($results.Count -ge $Limit) {
                return @($results)
            }
        }
    }

    return @($results)
}
