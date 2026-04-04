# tools/Remove-Files.ps1
<#
.CLAW_NAME
    Remove-Files
.CLAW_DESCRIPTION
    Deletes a list of specific file paths. Sends files to the Recycle Bin by default — use Permanent=true only when explicitly asked. Always provide exact full paths. Never guess paths — use Search-Files first to confirm what exists before calling this tool. Delete batches are capped unless MaxDeleteCount is set explicitly to match the intended file count. Permanent delete is limited to one file per call.
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

        [bool]$Permanent = $false,

        [ValidateRange(1, 20)]
        [int]$MaxDeleteCount = 5
    )

    # Load VisualBasic assembly for Recycle Bin support
    Add-Type -AssemblyName Microsoft.VisualBasic

    $deleted  = @()
    $failed   = @()
    $notFound = @()
    $blocked  = @()

    if (@($Paths).Count -gt $MaxDeleteCount) {
        return [PSCustomObject]@{
            Deleted      = @()
            Failed       = @()
            NotFound     = @()
            Blocked      = @(
                [PSCustomObject]@{
                    Path   = ($Paths -join ', ')
                    Reason = "Delete request includes $(@($Paths).Count) paths, which exceeds MaxDeleteCount=$MaxDeleteCount. Raise MaxDeleteCount explicitly only when the user clearly asked for that many deletes."
                }
            )
            FilesDeleted = 0
            SpaceFreedMB = 0
            Destination  = if ($Permanent) { "Permanently deleted" } else { "Recycle Bin" }
        }
    }

    if ($Permanent -and @($Paths).Count -gt 1) {
        return [PSCustomObject]@{
            Deleted      = @()
            Failed       = @()
            NotFound     = @()
            Blocked      = @(
                [PSCustomObject]@{
                    Path   = ($Paths -join ', ')
                    Reason = 'Permanent delete is limited to one file per call. Split the request into separate confirmed deletes.'
                }
            )
            FilesDeleted = 0
            SpaceFreedMB = 0
            Destination  = "Permanently deleted"
        }
    }

    $protectedRoots = @(
        [System.Environment]::GetFolderPath('Windows'),
        [System.Environment]::GetFolderPath('System'),
        [System.Environment]::GetFolderPath('ProgramFiles'),
        ${env:ProgramFiles(x86)},
        $env:ProgramData
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        try {
            [System.IO.Path]::GetFullPath($_).TrimEnd('\')
        } catch {
            $_
        }
    } | Select-Object -Unique

    function Test-IsProtectedDeletePath {
        param(
            [string]$CandidatePath,
            [string[]]$ProtectedRoots
        )

        $normalizedPath = [System.IO.Path]::GetFullPath($CandidatePath).TrimEnd('\')
        foreach ($root in $ProtectedRoots) {
            if ($normalizedPath.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }

            if ($normalizedPath.StartsWith("$root\", [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        return $false
    }

    foreach ($path in $Paths) {
        $expandedPath = [System.Environment]::ExpandEnvironmentVariables($path)

        if (-not [System.IO.Path]::IsPathFullyQualified($expandedPath)) {
            $blocked += [PSCustomObject]@{
                Path   = $expandedPath
                Reason = 'Path must be fully qualified. Relative paths are not allowed for Remove-Files.'
            }
            continue
        }

        if (-not (Test-Path -LiteralPath $expandedPath -PathType Leaf)) {
            $notFound += $expandedPath
            continue
        }

        $file = Get-Item -LiteralPath $expandedPath -ErrorAction Stop
        $sizeMB = [math]::Round($file.Length / 1MB, 2)
        $resolvedPath = $file.FullName

        if (Test-IsProtectedDeletePath -CandidatePath $resolvedPath -ProtectedRoots $protectedRoots) {
            $blocked += [PSCustomObject]@{
                Path   = $resolvedPath
                Reason = 'Deletion from Windows, System, Program Files, or ProgramData locations is blocked by policy.'
            }
            continue
        }

        try {
            if ($Permanent) {
                Remove-Item -LiteralPath $resolvedPath -Force -ErrorAction Stop
            } else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                    $resolvedPath,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                )
            }
            $deleted += [PSCustomObject]@{
                Path      = $resolvedPath
                SizeMB    = $sizeMB
                Permanent = $Permanent
            }
        }
        catch {
            $failed += [PSCustomObject]@{
                Path  = $resolvedPath
                Error = $_.Exception.Message
            }
        }
    }

    $totalMB = [math]::Round(($deleted | Measure-Object -Property SizeMB -Sum).Sum, 2)

    [PSCustomObject]@{
        Deleted      = $deleted
        Failed       = $failed
        NotFound     = $notFound
        Blocked      = $blocked
        FilesDeleted = $deleted.Count
        SpaceFreedMB = $totalMB
        Destination  = if ($Permanent) { "Permanently deleted" } else { "Recycle Bin" }
    }
}
