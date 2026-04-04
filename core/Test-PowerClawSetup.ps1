function Test-PowerClawSetup {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.json')
    )

    $result = [ordered]@{
        ConfigPath         = $ConfigPath
        ConfigExists       = $false
        ConfigTemplatePaths = @(
            (Join-Path $PSScriptRoot '..\config.example.json'),
            (Join-Path $PSScriptRoot '..\config.claude.example.json'),
            (Join-Path $PSScriptRoot '..\config.openai.example.json')
        )
        Provider           = $null
        Model              = $null
        ApiKeyEnv          = $null
        ApiKeyPresent      = $false
        ModuleOnPsModulePath = $false
        LauncherOnPath     = $false
        PathEntriesChecked = @()
        Issues             = @()
        Recommendations    = @()
        Ready              = $false
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $result.Issues += "config.json not found at $ConfigPath"
        $result.Recommendations += "Create config.json from config.example.json, config.claude.example.json, or config.openai.example.json."
        return [PSCustomObject]$result
    }

    $result.ConfigExists = $true
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $result.Provider = $config.provider
    $result.Model = $config.model
    $result.ApiKeyEnv = $config.api_key_env

    $supportedProviders = @('claude', 'openai')
    if ($config.provider -notin $supportedProviders) {
        $result.Issues += "Unsupported provider '$($config.provider)'. Supported providers: $($supportedProviders -join ', ')."
        $result.Recommendations += "Set provider to 'claude' or 'openai' and choose the matching example config as your base: config.claude.example.json or config.openai.example.json."
    }

    if (-not $config.model) {
        $result.Issues += "No model configured in config.json."
    }

    if (-not $config.api_key_env) {
        $result.Issues += "No api_key_env configured in config.json."
    } else {
        $apiKey = [System.Environment]::GetEnvironmentVariable($config.api_key_env)
        $result.ApiKeyPresent = -not [string]::IsNullOrWhiteSpace($apiKey)
        if (-not $result.ApiKeyPresent) {
            $result.Issues += "Environment variable '$($config.api_key_env)' is not set."
            $result.Recommendations += "Set `$env:$($config.api_key_env) before running PowerClaw."
        }
    }

    switch ($config.provider) {
        'claude' {
            if ($config.api_key_env -and $config.api_key_env -ne 'CLAUDE_API_KEY') {
                $result.Recommendations += "Claude setups usually use api_key_env='CLAUDE_API_KEY'."
            }
        }
        'openai' {
            if ($config.api_key_env -and $config.api_key_env -ne 'OPENAI_API_KEY') {
                $result.Recommendations += "OpenAI setups usually use api_key_env='OPENAI_API_KEY'."
            }
        }
    }

    $module = Get-Module -ListAvailable PowerClaw | Sort-Object Version -Descending | Select-Object -First 1
    if ($module) {
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $module.Path)
        $psModuleEntries = @($env:PSModulePath -split ';' | Where-Object { $_ })
        $result.ModuleOnPsModulePath = $moduleRoot -in $psModuleEntries
        if (-not $result.ModuleOnPsModulePath) {
            $result.Recommendations += "Add the PowerClaw module root to PSModulePath if you want module auto-import in new shells."
        }
    } else {
        $result.Recommendations += "Install the module with Install-PowerClaw.ps1 or import it from the repo root."
    }

    $pathEntries = @($env:PATH -split ';' | Where-Object { $_ })
    $result.PathEntriesChecked = $pathEntries
    foreach ($entry in $pathEntries) {
        if (Test-Path -LiteralPath (Join-Path $entry 'powerclaw.ps1')) {
            $result.LauncherOnPath = $true
            break
        }
    }
    if (-not $result.LauncherOnPath) {
        $result.Recommendations += "Add your launcher directory to PATH if you want 'powerclaw' to work in a fresh shell."
    }

    $result.Ready = ($result.Issues.Count -eq 0)
    if ($result.Ready) {
        $result.Recommendations += "Setup looks good. Run: powerclaw -UseStub ""hello"""
    }

    [PSCustomObject]$result
}
