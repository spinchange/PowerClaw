# tools/Get-StorageStatus.ps1
<#
.CLAW_NAME
    Get-StorageStatus
.CLAW_DESCRIPTION
    Returns disk usage, free space, and largest folders for drives on the system. Use this to check how much space is left, which drives are nearly full, or what's consuming the most storage.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    SystemInfo
#>
function Get-StorageStatus {
    [CmdletBinding()]
    param(
        [ValidateSet("Summary", "Drives", "LargestFolders")]
        [string]$View = "Summary",

        [string]$ScanPath = $env:USERPROFILE,

        [ValidateRange(1, 50)]
        [int]$TopFolders = 10
    )

    # ── Drive summary ──
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } | ForEach-Object {
        $total = $_.Used + $_.Free
        [PSCustomObject]@{
            Drive       = $_.Name
            Root        = $_.Root
            UsedGB      = [math]::Round($_.Used / 1GB, 2)
            FreeGB      = [math]::Round($_.Free / 1GB, 2)
            TotalGB     = [math]::Round($total / 1GB, 2)
            PercentFull = if ($total -gt 0) { [math]::Round(($_.Used / $total) * 100, 1) } else { 0 }
        }
    }

    if ($View -eq "Drives") { return $drives }

    # ── Largest folders under ScanPath ──
    $largestFolders = $null
    if ($View -in @("Summary", "LargestFolders")) {
        $largestFolders = Get-ChildItem -Path $ScanPath -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $size = (Get-ChildItem $_.FullName -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                [PSCustomObject]@{
                    Folder  = $_.FullName
                    SizeGB  = [math]::Round($size / 1GB, 2)
                    SizeMB  = [math]::Round($size / 1MB, 0)
                }
            } |
            Sort-Object SizeGB -Descending |
            Select-Object -First $TopFolders
    }

    switch ($View) {
        "LargestFolders" { $largestFolders }
        "Summary" {
            [PSCustomObject]@{
                Drives         = $drives
                LargestFolders = $largestFolders
                ScanPath       = $ScanPath
            }
        }
    }
}
