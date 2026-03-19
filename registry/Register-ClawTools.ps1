# registry/Register-ClawTools.ps1

function Register-ClawTools {
    [CmdletBinding()]
    param(
        [string]$ToolsPath = (Join-Path $PSScriptRoot '..\tools'),
        [string]$ManifestPath = (Join-Path $PSScriptRoot '..\tools-manifest.json')
    )

    # Load allowlist
    $manifest = if (Test-Path $ManifestPath) {
        Get-Content $ManifestPath -Raw | ConvertFrom-Json
    } else {
        Write-Warning "No tools-manifest.json found — no tools will be enabled."
        return @()
    }

    $approved = $manifest.approved_tools
    $registry = @()

    foreach ($file in Get-ChildItem "$ToolsPath\*.ps1") {
        $content = Get-Content $file.FullName -Raw

        # Parse custom CLAW metadata from comment block
        $name = if ($content -match '\.CLAW_NAME\s+(\S+)') { $Matches[1] } else { $file.BaseName }
        $desc = if ($content -match '(?s)\.CLAW_DESCRIPTION\s+(.+?)(?=\n\s*\.\w|\n#>)') { $Matches[1] -replace '\s+', ' ' | ForEach-Object { $_.Trim() } } else { '' }
        $risk = if ($content -match '\.CLAW_RISK\s+(\S+)') { $Matches[1] } else { 'ReadOnly' }

        # Check allowlist
        if ($name -notin $approved) {
            Write-Verbose "Skipping unapproved tool: $name"
            continue
        }

        # Dot-source and capture function
        . $file.FullName
        $funcInfo = Get-Command -Name $name -ErrorAction SilentlyContinue

        if (-not $funcInfo) {
            Write-Warning "Tool file $($file.Name) does not define function $name"
            continue
        }

        # Parse AST for default values — reflection ($p.DefaultValue) always returns
        # null for function parameters; AST is the only reliable way to get literals
        # like 0, $false, and "". SafeGetValue() works on constant/literal nodes.
        $fileAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName, [ref]$null, [ref]$null)
        $funcAst = $fileAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $name
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

        # Extract parameter metadata
        $params = foreach ($p in $funcInfo.Parameters.Values) {
            # Skip common PS parameters
            if ($p.Name -in @('Verbose','Debug','ErrorAction','WarningAction',
                'InformationAction','ErrorVariable','WarningVariable',
                'InformationVariable','OutVariable','OutBuffer','PipelineVariable',
                'ProgressAction')) { continue }

            $paramInfo = @{
                Name     = $p.Name
                Type     = $p.ParameterType.Name
                Required = $p.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory -contains $true
            }

            # Capture ValidateSet
            $valSet = $p.Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] })
            if ($valSet) { $paramInfo.Enum = $valSet[0].ValidValues }

            # Capture ValidateRange
            $valRange = $p.Attributes.Where({ $_ -is [System.Management.Automation.ValidateRangeAttribute] })
            if ($valRange) {
                $paramInfo.Min = $valRange[0].MinRange
                $paramInfo.Max = $valRange[0].MaxRange
            }

            # Capture default from AST lookup (handles 0, $false, "" correctly)
            if ($astDefaults.ContainsKey($p.Name)) { $paramInfo.Default = $astDefaults[$p.Name] }

            [PSCustomObject]$paramInfo
        }

        $registry += [PSCustomObject]@{
            Name        = $name
            Description = $desc
            Risk        = $risk
            Parameters  = @($params)
            ScriptBlock = (Get-Item "Function:\$name").ScriptBlock
            SourceFile  = $file.FullName
        }
    }

    Write-Host "[PowerClaw] Registered $($registry.Count) tools: $($registry.Name -join ', ')"
    return $registry
}
