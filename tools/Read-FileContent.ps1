# tools/Read-FileContent.ps1
<#
.CLAW_NAME
    Read-FileContent
.CLAW_DESCRIPTION
    Reads the content of a file and returns it as text. Use this to let Claude read and reason about any file — logs, configs, scripts, journals, READMEs, CSVs. Automatically refuses files over the size limit to protect context.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    Filesystem
#>
function Read-FileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateRange(1, 500)]
        [int]$MaxLines = 200,

        [ValidateRange(1, 50)]
        [int]$MaxSizeMB = 5
    )

    # Expand any $env: references Claude may pass
    $Path = [System.Environment]::ExpandEnvironmentVariables($Path)

    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }

    $file = Get-Item $Path
    $sizeMB = [math]::Round($file.Length / 1MB, 2)

    if ($sizeMB -gt $MaxSizeMB) {
        throw "File is $sizeMB MB — too large to read (limit: $MaxSizeMB MB). Use Search-Files to find a smaller file or ask for a specific section."
    }

    $lines = Get-Content $Path -ErrorAction Stop
    $totalLines = $lines.Count
    $truncated = $totalLines -gt $MaxLines

    $output = [PSCustomObject]@{
        Path        = $file.FullName
        SizeMB      = $sizeMB
        TotalLines  = $totalLines
        LinesShown  = [math]::Min($totalLines, $MaxLines)
        Truncated   = $truncated
        Content     = ($lines | Select-Object -First $MaxLines) -join "`n"
    }

    if ($truncated) {
        Write-Warning "File has $totalLines lines — showing first $MaxLines. Pass a higher MaxLines if you need more."
    }

    $output
}
