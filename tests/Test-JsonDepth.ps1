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

# ── Test falsy-but-valid metadata through the full registry→schema pipeline ──
# This tests the actual failing path: Register-ClawTools extracts defaults via
# AST parsing, then ConvertTo-ClaudeToolSchema serializes them.
Write-Host "`n── Falsy defaults: registry extraction (AST path) ──" -ForegroundColor Cyan

$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "registry\ConvertTo-ToolSchema.ps1")

# Write a minimal tool to a temp file so we can run the AST extraction on it —
# the same path Register-ClawTools takes for real tool files.
$tmpTool = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
Set-Content $tmpTool @'
function Test-FalsyDefaultsTool {
    [CmdletBinding()]
    param(
        [int]$MinSize    = 0,
        [bool]$Aggregate = $false,
        [string]$Label   = ""
    )
}
'@

# Replicate the AST extraction logic from Register-ClawTools
. $tmpTool
$funcInfo = Get-Command -Name "Test-FalsyDefaultsTool"
$fileAst  = [System.Management.Automation.Language.Parser]::ParseFile($tmpTool, [ref]$null, [ref]$null)
$funcAst  = $fileAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq "Test-FalsyDefaultsTool"
}, $true)
$astDefaults = @{}
if ($funcAst -and $funcAst.Body.ParamBlock) {
    foreach ($astParam in $funcAst.Body.ParamBlock.Parameters) {
        $pName = $astParam.Name.VariablePath.UserPath
        if ($null -ne $astParam.DefaultValue) {
            try { $astDefaults[$pName] = $astParam.DefaultValue.SafeGetValue() } catch {}
        }
    }
}
Remove-Item $tmpTool -ErrorAction SilentlyContinue

$skip = @('Verbose','Debug','ErrorAction','WarningAction','InformationAction',
    'ErrorVariable','WarningVariable','InformationVariable','OutVariable',
    'OutBuffer','PipelineVariable','ProgressAction')
$extracted = foreach ($p in $funcInfo.Parameters.Values) {
    if ($p.Name -in $skip) { continue }
    $pi = @{ Name = $p.Name; Type = $p.ParameterType.Name; Required = $false }
    if ($astDefaults.ContainsKey($p.Name)) { $pi.Default = $astDefaults[$p.Name] }
    [PSCustomObject]$pi
}

$testTool = [PSCustomObject]@{
    Name        = "Test-FalsyDefaultsTool"
    Description = "Regression tool for falsy default extraction"
    Parameters  = @($extracted)
}

$schema = ConvertTo-ClaudeToolSchema $testTool
$json   = $schema | ConvertTo-Json -Depth 10

Assert-Contains    "Registry AST: MinSize=0 extracted and emitted"          $json '"default": 0'
Assert-Contains    "Registry AST: Aggregate=false extracted and emitted"    $json '"default": false'
Assert-Contains    "Registry AST: Label=empty string extracted and emitted" $json '"default": ""'

# Test non-literal (expression) defaults fall back to AST text
Write-Host "`n── Falsy defaults: non-literal expression fallback ──" -ForegroundColor Cyan

$tmpExpr = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
Set-Content $tmpExpr @'
function Test-ExpressionDefaultTool {
    [CmdletBinding()]
    param(
        [string]$Scope = $env:USERPROFILE
    )
}
'@

. $tmpExpr
$funcInfoExpr = Get-Command -Name "Test-ExpressionDefaultTool"
$fileAstExpr  = [System.Management.Automation.Language.Parser]::ParseFile($tmpExpr, [ref]$null, [ref]$null)
$funcAstExpr  = $fileAstExpr.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq "Test-ExpressionDefaultTool"
}, $true)
$astDefaultsExpr = @{}
if ($funcAstExpr -and $funcAstExpr.Body.ParamBlock) {
    foreach ($astParam in $funcAstExpr.Body.ParamBlock.Parameters) {
        $pName = $astParam.Name.VariablePath.UserPath
        if ($null -ne $astParam.DefaultValue) {
            try {
                $astDefaultsExpr[$pName] = $astParam.DefaultValue.SafeGetValue()
            } catch {
                $astDefaultsExpr[$pName] = $astParam.DefaultValue.Extent.Text
            }
        }
    }
}
Remove-Item $tmpExpr -ErrorAction SilentlyContinue

$exprExtracted = foreach ($p in $funcInfoExpr.Parameters.Values) {
    if ($p.Name -in $skip) { continue }
    $pi = @{ Name = $p.Name; Type = $p.ParameterType.Name; Required = $false }
    if ($astDefaultsExpr.ContainsKey($p.Name)) { $pi.Default = $astDefaultsExpr[$p.Name] }
    [PSCustomObject]$pi
}
$exprTool   = [PSCustomObject]@{ Name = "Test-ExpressionDefaultTool"; Description = "expr default test"; Parameters = @($exprExtracted) }
$exprSchema = ConvertTo-ClaudeToolSchema $exprTool
$exprJson   = $exprSchema | ConvertTo-Json -Depth 10

Assert-Contains "Expression default: Scope emits AST text fallback" $exprJson '$env:USERPROFILE'

# Also verify the serializer layer still works correctly in isolation
Write-Host "`n── Falsy defaults: serializer layer ──" -ForegroundColor Cyan

$directTool = [PSCustomObject]@{
    Name        = "Test-FalsyDefaults"
    Description = "Tool with falsy but valid parameter metadata"
    Parameters  = @(
        [PSCustomObject]@{ Name = "MinSize"; Type = "Int32";   Required = $false; Min = 0;      Max = $null;  Default = $null;  Enum = $null }
        [PSCustomObject]@{ Name = "Enabled"; Type = "Boolean"; Required = $false; Min = $null;  Max = $null;  Default = $false; Enum = $null }
        [PSCustomObject]@{ Name = "Label";   Type = "String";  Required = $false; Min = $null;  Max = $null;  Default = "";     Enum = $null }
    )
}

$directSchema = ConvertTo-ClaudeToolSchema $directTool
$directJson   = $directSchema | ConvertTo-Json -Depth 10

Assert-Contains    "Serializer: Min=0 emits minimum:0"         $directJson '"minimum": 0'
Assert-Contains    "Serializer: Default=$false emits default"  $directJson '"default": false'
Assert-Contains    "Serializer: Default=empty emits default"   $directJson '"default": ""'
Assert-NotContains "Serializer: Null Min not emitted"          $directJson '"minimum": null'
Assert-NotContains "Serializer: Null Max not emitted"          $directJson '"maximum": null'

# ── Summary ──
Write-Host "`n── Results: $pass passed, $fail failed ──" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
