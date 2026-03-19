# tests/Test-JsonDepth.ps1
# Spike: verify tool schemas survive round-trip serialization at various depths.
# Run this before Phase 2 to confirm your schemas won't silently corrupt.
#
# Usage:
#   pwsh -File .\tests\Test-JsonDepth.ps1

$pass = 0
$fail = 0

function Assert-Contains {
    param([string]$Label, [string]$Json, [string]$Expected)
    if ($Json -match [regex]::Escape($Expected)) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [FAIL] $Label — expected to find: $Expected" -ForegroundColor Red
        Write-Host "         Got: $($Json.Substring(0, [Math]::Min(200, $Json.Length)))" -ForegroundColor DarkRed
        $script:fail++
    }
}

function Assert-NotContains {
    param([string]$Label, [string]$Json, [string]$Unwanted)
    if ($Json -notmatch [regex]::Escape($Unwanted)) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [FAIL] $Label — should NOT contain: $Unwanted" -ForegroundColor Red
        $script:fail++
    }
}

# ── Test schema ──
$schema = @{
    name        = "Get-DirectoryListing"
    description = "Lists files in a directory"
    input_schema = @{
        type       = "object"
        properties = @{
            Path   = @{ type = "string" }
            Filter = @{ type = "string"; default = "*" }
            Limit  = @{ type = "integer"; minimum = 1; maximum = 100 }
        }
        required = @("Path")
    }
}

Write-Host "`n── Depth 2 (broken — what PS defaults to) ──" -ForegroundColor Yellow
$depth2 = $schema | ConvertTo-Json -Depth 2
Write-Host $depth2
Assert-Contains "Depth 2: confirms truncation bug (hashtable strings appear)" $depth2 "System.Collections.Hashtable"

Write-Host "`n── Depth 10 (correct) ──" -ForegroundColor Cyan
$depth10 = $schema | ConvertTo-Json -Depth 10
Write-Host $depth10
Assert-Contains "Depth 10: Path property present"    $depth10 '"Path"'
Assert-Contains "Depth 10: Filter default present"   $depth10 '"default": "*"'
Assert-Contains "Depth 10: Limit minimum present"    $depth10 '"minimum": 1'
Assert-Contains "Depth 10: required array present"   $depth10 '"required"'

# ── Test PSCustomObject → hashtable conversion ──
Write-Host "`n── PSCustomObject splat conversion ──" -ForegroundColor Cyan

$jsonInput = '{"SortBy": "Memory", "Count": 10}'
$parsed = $jsonInput | ConvertFrom-Json

Write-Host "  Type after ConvertFrom-Json: $($parsed.GetType().FullName)"

$hash = @{}
foreach ($prop in $parsed.PSObject.Properties) {
    $hash[$prop.Name] = $prop.Value
}

if ($hash['SortBy'] -eq 'Memory' -and $hash['Count'] -eq 10) {
    Write-Host "  [PASS] PSCustomObject → hashtable conversion" -ForegroundColor Green
    $pass++
} else {
    Write-Host "  [FAIL] Conversion lost values: $($hash | ConvertTo-Json)" -ForegroundColor Red
    $fail++
}

# ── Test message array round-trip ──
Write-Host "`n── Message array round-trip (depth 10) ──" -ForegroundColor Cyan

$messages = @(
    @{ role = "user"; content = "Hello" }
    @{
        role    = "assistant"
        content = @(@{
            type  = "tool_use"
            id    = "toolu_abc123"
            name  = "Get-TopProcesses"
            input = @{ SortBy = "CPU"; Count = 5 }
        })
    }
    @{
        role    = "user"
        content = @(@{
            type        = "tool_result"
            tool_use_id = "toolu_abc123"
            content     = "chrome 45.2 MB\npwsh 12.1 MB"
        })
    }
)

$json = $messages | ConvertTo-Json -Depth 10
Assert-Contains "Message array: tool_use type present"   $json '"tool_use"'
Assert-Contains "Message array: tool_use_id present"     $json '"tool_use_id"'
Assert-Contains "Message array: tool input SortBy"       $json '"SortBy"'

# ── Test falsy-but-valid metadata (regression for ConvertTo-ToolSchema fix) ──
Write-Host "`n── Falsy-but-valid schema metadata ──" -ForegroundColor Cyan

$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "registry\ConvertTo-ToolSchema.ps1")

$testTool = [PSCustomObject]@{
    Name        = "Test-FalsyDefaults"
    Description = "Tool with falsy but valid parameter metadata"
    Parameters  = @(
        [PSCustomObject]@{ Name = "MinSize"; Type = "Int32";   Required = $false; Min = 0;      Max = $null;  Default = $null;  Enum = $null }
        [PSCustomObject]@{ Name = "Enabled"; Type = "Boolean"; Required = $false; Min = $null;  Max = $null;  Default = $false; Enum = $null }
        [PSCustomObject]@{ Name = "Label";   Type = "String";  Required = $false; Min = $null;  Max = $null;  Default = "";     Enum = $null }
    )
}

$schema = ConvertTo-ClaudeToolSchema $testTool
$json = $schema | ConvertTo-Json -Depth 10

Assert-Contains    "Falsy Min=0 emits minimum:0"        $json '"minimum": 0'
Assert-Contains    "Falsy Default=false emits default"  $json '"default": false'
Assert-Contains    "Falsy Default=empty emits default"  $json '"default": ""'
Assert-NotContains "Null Min does not emit minimum"     $json '"minimum": null'
Assert-NotContains "Null Max does not emit maximum"     $json '"maximum": null'

# ── Summary ──
Write-Host "`n── Results: $pass passed, $fail failed ──" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
