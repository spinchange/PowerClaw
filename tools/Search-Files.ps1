# tools/Search-Files.ps1
<#
.CLAW_NAME
    Search-Files
.CLAW_DESCRIPTION
    Searches the Windows Search index for files by name, content, size, type, or kind (music/video/picture/document). Use Kind for broad category questions. Use Aggregate=true for "how much" or "how many" questions to get a count and total size instead of a file list.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    Filesystem
#>
function Search-Files {
    [CmdletBinding()]
    param(
        [string]$Scope = $env:USERPROFILE,

        [string]$FileName,

        [string]$ContentQuery,

        [string]$Extension,

        [ValidateSet("music", "video", "picture", "document", "email", "program", "")]
        [string]$Kind = "",

        [ValidateRange(1, 500)]
        [int]$Limit = 25,

        [ValidateSet("Size", "DateModified", "Name")]
        [string]$SortBy = "Size",

        [int]$MinSizeMB = 0,

        [bool]$Aggregate = $false
    )

    $where = @("SCOPE='file:$Scope'")

    if ($FileName)     { $where += "System.FileName LIKE '$($FileName -replace '\*','%')'" }
    if ($Extension)    { $where += "System.FileExtension = '.$($Extension.TrimStart('.'))'" }
    if ($Kind)         { $where += "System.Kind = '$Kind'" }
    if ($ContentQuery) { $where += "CONTAINS(System.Search.Contents, '$ContentQuery')" }
    if ($MinSizeMB -gt 0) { $where += "System.Size >= $($MinSizeMB * 1MB)" }

    $sortCol = switch ($SortBy) {
        'Size'         { 'System.Size DESC' }
        'DateModified' { 'System.DateModified DESC' }
        'Name'         { 'System.ItemName ASC' }
    }

    $sql = "SELECT System.ItemName, System.ItemPathDisplay, System.Size, System.DateModified " +
           "FROM SystemIndex WHERE $($where -join ' AND ') ORDER BY $sortCol"

    try {
        $conn = New-Object System.Data.OleDb.OleDbConnection(
            "Provider=Search.CollatorDSO.1;Extended Properties='Application=Windows'"
        )
        $conn.Open()
        $cmd     = $conn.CreateCommand()
        $cmd.CommandText = $sql
        $adapter = New-Object System.Data.OleDb.OleDbDataAdapter($cmd)
        $ds      = New-Object System.Data.DataSet
        $adapter.Fill($ds) | Out-Null
        $conn.Close()
    }
    catch {
        throw "Windows Search query failed: $_"
    }

    if ($Aggregate) {
        $rows = $ds.Tables[0].Rows
        $totalBytes = ($rows | ForEach-Object {
            if ($_['SYSTEM.SIZE'] -ne [DBNull]::Value) { [double]$_['SYSTEM.SIZE'] } else { 0 }
        } | Measure-Object -Sum).Sum
        [PSCustomObject]@{
            FileCount   = $rows.Count
            TotalSizeMB = [math]::Round($totalBytes / 1MB, 1)
            TotalSizeGB = [math]::Round($totalBytes / 1GB, 2)
        }
    }
    else {
        $ds.Tables[0] | Select-Object -First $Limit | ForEach-Object {
            [PSCustomObject]@{
                Name         = $_['SYSTEM.ITEMNAME']
                Path         = $_['SYSTEM.ITEMPATHDISPLAY']
                SizeMB       = if ($_['SYSTEM.SIZE'] -ne [DBNull]::Value) { [math]::Round($_['SYSTEM.SIZE'] / 1MB, 2) } else { 0 }
                DateModified = $_['SYSTEM.DATEMODIFIED']
            }
        }
    }
}
