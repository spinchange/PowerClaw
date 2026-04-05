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

        [datetime]$After,

        [datetime]$Before,

        [bool]$Aggregate = $false
    )

    function ConvertTo-SearchSqlLiteral {
        param([string]$Value)
        return $Value -replace "'", "''"
    }

    $scopeLiteral = ConvertTo-SearchSqlLiteral "file:$Scope"
    $where = @("SCOPE='$scopeLiteral'")

    if ($FileName) {
        $fileNamePattern = ConvertTo-SearchSqlLiteral ($FileName -replace '\*', '%')
        $where += "System.FileName LIKE '$fileNamePattern'"
    }
    if ($Extension) {
        $extensionLiteral = ConvertTo-SearchSqlLiteral ".$($Extension.TrimStart('.'))"
        $where += "System.FileExtension = '$extensionLiteral'"
    }
    if ($Kind) {
        $kindLiteral = ConvertTo-SearchSqlLiteral $Kind
        $where += "System.Kind = '$kindLiteral'"
    }
    if ($ContentQuery) {
        $contentLiteral = ConvertTo-SearchSqlLiteral $ContentQuery
        $where += "CONTAINS(System.Search.Contents, '$contentLiteral')"
    }
    if ($MinSizeMB -gt 0) { $where += "System.Size >= $($MinSizeMB * 1MB)" }

    $sortCol = switch ($SortBy) {
        'Size'         { 'System.Size DESC' }
        'DateModified' { 'System.DateModified DESC' }
        'Name'         { 'System.ItemName ASC' }
    }

    $needsPostFilter = $PSBoundParameters.ContainsKey('After') -or $PSBoundParameters.ContainsKey('Before')
    $topClause = if ($Aggregate -or $needsPostFilter) { "" } else { "TOP $Limit " }
    $sql = "SELECT ${topClause}System.ItemName, System.ItemPathDisplay, System.Size, System.DateModified " +
           "FROM SystemIndex WHERE $($where -join ' AND ') ORDER BY $sortCol"

    $conn = $null
    $adapter = $null

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
    }
    catch {
        throw "Windows Search query failed: $_"
    }
    finally {
        if ($conn) {
            if ($conn.State -ne [System.Data.ConnectionState]::Closed) {
                $conn.Close()
            }
            $conn.Dispose()
        }
        if ($adapter) {
            $adapter.Dispose()
        }
    }

    $resultRows = @(
        $ds.Tables[0].Rows | ForEach-Object {
            [PSCustomObject]@{
                Name         = $_['SYSTEM.ITEMNAME']
                Path         = $_['SYSTEM.ITEMPATHDISPLAY']
                SizeMB       = if ($_['SYSTEM.SIZE'] -ne [DBNull]::Value) { [math]::Round($_['SYSTEM.SIZE'] / 1MB, 2) } else { 0 }
                DateModified = $_['SYSTEM.DATEMODIFIED']
            }
        }
    )

    if ($PSBoundParameters.ContainsKey('After')) {
        $resultRows = @($resultRows | Where-Object { $_.DateModified -ge $After })
    }
    if ($PSBoundParameters.ContainsKey('Before')) {
        $resultRows = @($resultRows | Where-Object { $_.DateModified -le $Before })
    }

    if ($Aggregate) {
        $totalBytes = ($resultRows | ForEach-Object {
            if ($_.SizeMB -ne $null) { [double]$_.SizeMB * 1MB } else { 0 }
        } | Measure-Object -Sum).Sum
        [PSCustomObject]@{
            FileCount   = $resultRows.Count
            TotalSizeMB = [math]::Round($totalBytes / 1MB, 1)
            TotalSizeGB = [math]::Round($totalBytes / 1GB, 2)
        }
    }
    else {
        @($resultRows | Select-Object -First $Limit)
    }
}
