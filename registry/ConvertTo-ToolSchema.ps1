# registry/ConvertTo-ToolSchema.ps1

function ConvertTo-ClaudeToolSchema {
    [CmdletBinding()]
    param([Parameter(Mandatory)][PSCustomObject]$Tool)

    $properties = @{}
    $required = @()

    foreach ($p in $Tool.Parameters) {
        $prop = @{ type = (ConvertTo-JsonType $p.Type) }
        if ($p.Enum)    { $prop.enum = $p.Enum }
        if ($p.Min)     { $prop.minimum = $p.Min }
        if ($p.Max)     { $prop.maximum = $p.Max }
        if ($p.Default) { $prop.default = $p.Default }
        $properties[$p.Name] = $prop
        if ($p.Required) { $required += $p.Name }
    }

    return @{
        name         = $Tool.Name
        description  = $Tool.Description
        input_schema = @{
            type       = "object"
            properties = $properties
            required   = $required
        }
    }
}

function ConvertTo-JsonType {
    param([string]$PSTypeName)
    switch ($PSTypeName) {
        'String'  { 'string' }
        'Int32'   { 'integer' }
        'Int64'   { 'integer' }
        'Double'  { 'number' }
        'Boolean' { 'boolean' }
        'Switch'  { 'boolean' }
        default   { 'string' }
    }
}
