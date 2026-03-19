# tools/Remove-Files.ps1
<#
.CLAW_NAME
    Remove-Files
.CLAW_DESCRIPTION
    Deletes a list of specific file paths. Sends files to the Recycle Bin by default — use Permanent=true only when explicitly asked. Always provide exact full paths. Never guess paths — use Search-Files first to confirm what exists before calling this tool.
.CLAW_RISK
    Write
.CLAW_CATEGORY
    Filesystem
#>
function Remove-Files {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [bool]$Permanent = $false
    )

    # Load VisualBasic assembly for Recycle Bin support
    Add-Type -AssemblyName Microsoft.VisualBasic

    $deleted  = @()
    $failed   = @()
    $notFound = @()

    foreach ($path in $Paths) {
        $path = [System.Environment]::ExpandEnvironmentVariables($path)

        if (-not (Test-Path $path -PathType Leaf)) {
            $notFound += $path
            continue
        }

        $file = Get-Item $path
        $sizeMB = [math]::Round($file.Length / 1MB, 2)

        try {
            if ($Permanent) {
                Remove-Item -Path $path -Force -ErrorAction Stop
            } else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                    $path,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                )
            }
            $deleted += [PSCustomObject]@{
                Path      = $path
                SizeMB    = $sizeMB
                Permanent = $Permanent
            }
        }
        catch {
            $failed += [PSCustomObject]@{
                Path  = $path
                Error = $_.Exception.Message
            }
        }
    }

    $totalMB = [math]::Round(($deleted | Measure-Object -Property SizeMB -Sum).Sum, 2)

    [PSCustomObject]@{
        Deleted      = $deleted
        Failed       = $failed
        NotFound     = $notFound
        FilesDeleted = $deleted.Count
        SpaceFreedMB = $totalMB
        Destination  = if ($Permanent) { "Permanently deleted" } else { "Recycle Bin" }
    }
}
