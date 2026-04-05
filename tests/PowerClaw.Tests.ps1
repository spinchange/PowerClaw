BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:ModulePath = Join-Path $script:RepoRoot 'PowerCLAW.psd1'
    $script:TempRoot = [System.IO.Path]::GetTempPath().TrimEnd('\')

    Import-Module $script:ModulePath -Force

    . (Join-Path $script:RepoRoot 'registry\Register-ClawTools.ps1')
    . (Join-Path $script:RepoRoot 'registry\ConvertTo-ToolSchema.ps1')
    . (Join-Path $script:RepoRoot 'core\Invoke-ClawLoop.ps1')
    . (Join-Path $script:RepoRoot 'core\Invoke-CleanupSummary.ps1')
    . (Join-Path $script:RepoRoot 'core\Invoke-RecentChangesSummary.ps1')
    . (Join-Path $script:RepoRoot 'core\Invoke-SystemTriage.ps1')
    . (Join-Path $script:RepoRoot 'client\Send-ClawRequest.ps1')
    . (Join-Path $script:RepoRoot 'client\providers\Send-OpenAiRequest.ps1')
    . (Join-Path $script:RepoRoot 'client\providers\Send-ClaudeRequest.ps1')
    . (Join-Path $script:RepoRoot 'tools\Fetch-WebPage.ps1')
    . (Join-Path $script:RepoRoot 'tools\Get-SystemSummary.ps1')
    . (Join-Path $script:RepoRoot 'tools\Get-ServiceStatus.ps1')
    . (Join-Path $script:RepoRoot 'tools\Get-EventLogEntries.ps1')
    . (Join-Path $script:RepoRoot 'tools\Get-StorageStatus.ps1')
    . (Join-Path $script:RepoRoot 'tools\Get-TopProcesses.ps1')
    . (Join-Path $script:RepoRoot 'tools\Search-Files.ps1')
    . (Join-Path $script:RepoRoot 'tools\Search-LocalKnowledge.ps1')
    . (Join-Path $script:RepoRoot 'tools\Get-DirectoryListing.ps1')
    . (Join-Path $script:RepoRoot 'tools\Remove-Files.ps1')
    . (Join-Path $script:RepoRoot 'tools\Get-RecentChangesSummary.ps1')
}

Describe 'PowerClaw module' {
    It 'imports the module and exports Invoke-PowerClaw' {
        (Get-Command Invoke-PowerClaw -ErrorAction Stop).Name | Should -Be 'Invoke-PowerClaw'
    }

    It 'exports the powerclaw alias for interactive use' {
        $alias = Get-Command powerclaw -ErrorAction Stop

        $alias.CommandType | Should -Be 'Alias'
        $alias.Definition | Should -Be 'Invoke-PowerClaw'
    }

    It 'ships a launcher script that works from the repo root' {
        $launcherPath = Join-Path $script:RepoRoot 'powerclaw.ps1'
        $output = pwsh -NoProfile -File $launcherPath -UseStub 'anything' | Out-String

        $output | Should -Match '\[Stub\]'
    }

    It 'exports Test-PowerClawSetup' {
        (Get-Command Test-PowerClawSetup -ErrorAction Stop).Name | Should -Be 'Test-PowerClawSetup'
    }

    It 'exports Invoke-SystemTriage' {
        (Get-Command Invoke-SystemTriage -ErrorAction Stop).Name | Should -Be 'Invoke-SystemTriage'
    }

    It 'exports Invoke-CleanupSummary' {
        (Get-Command Invoke-CleanupSummary -ErrorAction Stop).Name | Should -Be 'Invoke-CleanupSummary'
    }

    It 'exports Invoke-RecentChangesSummary' {
        (Get-Command Invoke-RecentChangesSummary -ErrorAction Stop).Name | Should -Be 'Invoke-RecentChangesSummary'
    }

    It 'ships a web runtime installer script that bootstraps Playwright' {
        $installerPath = Join-Path $script:RepoRoot 'Install-PowerClawWebRuntime.ps1'
        $runtimeRoot = Join-Path $script:TempRoot 'powerclaw-web-runtime-install'
        $commandLog = [System.Collections.Generic.List[string]]::new()

        Remove-Item -LiteralPath $runtimeRoot -Recurse -Force -ErrorAction SilentlyContinue

        try {
            function global:dotnet {
                param(
                    [Parameter(ValueFromRemainingArguments = $true)]
                    [object[]]$Args
                )

                $commandLog.Add("dotnet $($Args -join ' ')")

                if ($Args.Count -ge 2 -and $Args[0] -eq 'new' -and $Args[1] -eq 'console') {
                    $projectIndex = [Array]::IndexOf($Args, '-n')
                    $frameworkIndex = [Array]::IndexOf($Args, '--framework')
                    $projectName = [string]$Args[$projectIndex + 1]
                    $framework = [string]$Args[$frameworkIndex + 1]
                    $projectRoot = Join-Path (Get-Location) $projectName
                    $playwrightScript = Join-Path $projectRoot "bin\Debug\$framework\playwright.ps1"

                    New-Item -ItemType Directory -Path (Split-Path -Parent $playwrightScript) -Force | Out-Null
                    Set-Content -LiteralPath $playwrightScript -Value '# mock playwright installer'
                }
            }

            function global:pwsh {
                param(
                    [Parameter(ValueFromRemainingArguments = $true)]
                    [object[]]$Args
                )

                $commandLog.Add("pwsh $($Args -join ' ')")
            }

            & $installerPath -RuntimeRoot $runtimeRoot

            Test-Path -LiteralPath (Join-Path $runtimeRoot 'PwHost\bin\Debug\net10.0\playwright.ps1') | Should -BeTrue
            $joinedCommands = @($commandLog) -join "`n"
            $joinedCommands | Should -Match 'dotnet new console'
            $joinedCommands | Should -Match 'dotnet add package Microsoft\.Playwright'
            $joinedCommands | Should -Match 'dotnet build'
            $joinedCommands | Should -Match 'pwsh -File .* install chromium'
        }
        finally {
            Remove-Item Function:\global:dotnet -ErrorAction SilentlyContinue
            Remove-Item Function:\global:pwsh -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $runtimeRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Setup validation' {
    It 'reports ready when config and key are valid' {
        $configPath = Join-Path $script:TempRoot 'powerclaw-setup-valid.json'
        $webRuntimeRoot = Join-Path $script:TempRoot 'powerclaw-playwright-test\bin\Debug'
        $env:POWERCLAW_TEST_SETUP_KEY = 'test-key'
        $env:POWERCLAW_PLAYWRIGHT_BUILD = $webRuntimeRoot
        Set-Content -LiteralPath $configPath -Value @'
{
  "provider": "openai",
  "model": "gpt-test",
  "api_key_env": "POWERCLAW_TEST_SETUP_KEY",
  "max_tokens": 256,
  "max_steps": 2,
  "max_output_chars": 1000,
  "log_file": "powerclaw.log"
}
'@
        try {
            New-Item -ItemType Directory -Path (Join-Path $webRuntimeRoot 'net10.0') -Force | Out-Null

            $result = Test-PowerClawSetup -ConfigPath $configPath
            $result.Ready | Should -BeTrue
            $result.Provider | Should -Be 'openai'
            $result.WebFetchReady | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath (Join-Path $script:TempRoot 'powerclaw-playwright-test') -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
            Remove-Item Env:\POWERCLAW_PLAYWRIGHT_BUILD -ErrorAction SilentlyContinue
            Remove-Item Env:\POWERCLAW_TEST_SETUP_KEY -ErrorAction SilentlyContinue
        }
    }

    It 'reports missing key and bad provider clearly' {
        $configPath = Join-Path $script:TempRoot 'powerclaw-setup-invalid.json'
        Set-Content -LiteralPath $configPath -Value @'
{
  "provider": "gemini",
  "model": "test-model",
  "api_key_env": "POWERCLAW_MISSING_KEY",
  "max_tokens": 256,
  "max_steps": 2,
  "max_output_chars": 1000,
  "log_file": "powerclaw.log"
}
'@
        try {
            $result = Test-PowerClawSetup -ConfigPath $configPath
            $result.Ready | Should -BeFalse
            @($result.Issues) -join ' ' | Should -Match 'Unsupported provider'
            @($result.Issues) -join ' ' | Should -Match 'POWERCLAW_MISSING_KEY'
            @($result.Recommendations) -join ' ' | Should -Match 'config\.openai\.example\.json'
        }
        finally {
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reports missing optional web runtime with the supported install command' {
        $configPath = Join-Path $script:TempRoot 'powerclaw-setup-web-missing.json'
        $env:POWERCLAW_TEST_SETUP_KEY = 'test-key'
        $env:POWERCLAW_PLAYWRIGHT_BUILD = Join-Path $script:TempRoot 'powerclaw-playwright-missing\bin\Debug'
        Set-Content -LiteralPath $configPath -Value @'
{
  "provider": "openai",
  "model": "gpt-test",
  "api_key_env": "POWERCLAW_TEST_SETUP_KEY",
  "max_tokens": 256,
  "max_steps": 2,
  "max_output_chars": 1000,
  "log_file": "powerclaw.log"
}
'@
        try {
            $result = Test-PowerClawSetup -ConfigPath $configPath
            $result.Ready | Should -BeTrue
            @($result.Warnings) -join ' ' | Should -Match 'POWERCLAW_PLAYWRIGHT_BUILD points to a missing path'
            @($result.Recommendations) -join ' ' | Should -Match 'Install-PowerClawWebRuntime\.ps1'
        }
        finally {
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
            Remove-Item Env:\POWERCLAW_PLAYWRIGHT_BUILD -ErrorAction SilentlyContinue
            Remove-Item Env:\POWERCLAW_TEST_SETUP_KEY -ErrorAction SilentlyContinue
        }
    }

    It 'reports an invalid POWERCLAW_PLAYWRIGHT_BUILD override explicitly' {
        $configPath = Join-Path $script:TempRoot 'powerclaw-setup-override.json'
        $env:POWERCLAW_TEST_SETUP_KEY = 'test-key'
        $env:POWERCLAW_PLAYWRIGHT_BUILD = Join-Path $script:TempRoot 'powerclaw-playwright-bad-override\bin\Debug'

        Set-Content -LiteralPath $configPath -Value @'
{
  "provider": "openai",
  "model": "gpt-test",
  "api_key_env": "POWERCLAW_TEST_SETUP_KEY",
  "max_tokens": 256,
  "max_steps": 2,
  "max_output_chars": 1000,
  "log_file": "powerclaw.log"
}
'@

        try {
            $result = Test-PowerClawSetup -ConfigPath $configPath
            $result.Ready | Should -BeTrue
            $result.WebFetchReady | Should -BeFalse
            @($result.Warnings) -join ' ' | Should -Match 'POWERCLAW_PLAYWRIGHT_BUILD points to a missing path'
            @($result.Recommendations) -join ' ' | Should -Match 'Install-PowerClawWebRuntime\.ps1'
        }
        finally {
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
            Remove-Item Env:\POWERCLAW_PLAYWRIGHT_BUILD -ErrorAction SilentlyContinue
            Remove-Item Env:\POWERCLAW_TEST_SETUP_KEY -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Tool behavior' {
    It 'sorts process output by WorkingSet64 when SortBy=Memory' {
        $actual = @(Get-TopProcesses -SortBy Memory -Count 5)

        $actual.Count | Should -Be 5
        @($actual.MemoryMB) | Should -Be @($actual.MemoryMB | Sort-Object -Descending)
    }

    It 'filters directory listings with inclusive After and Before bounds' {
        $tempDir = Join-Path $script:TempRoot "powerclaw-dir-filter-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        $olderPath = Join-Path $tempDir 'older.log'
        $middlePath = Join-Path $tempDir 'middle.log'
        $newerPath = Join-Path $tempDir 'newer.log'

        try {
            Set-Content -LiteralPath $olderPath -Value 'old'
            Set-Content -LiteralPath $middlePath -Value 'middle'
            Set-Content -LiteralPath $newerPath -Value 'new'

            (Get-Item -LiteralPath $olderPath).LastWriteTime = [datetime]'2026-04-01T08:00:00'
            (Get-Item -LiteralPath $middlePath).LastWriteTime = [datetime]'2026-04-02T12:00:00'
            (Get-Item -LiteralPath $newerPath).LastWriteTime = [datetime]'2026-04-03T18:30:00'

            $result = @(Get-DirectoryListing -Path $tempDir -Filter '*.log' -After ([datetime]'2026-04-02T12:00:00') -Before ([datetime]'2026-04-03T18:30:00') -Limit 10)

            @($result.Name) | Should -Be @('middle.log', 'newer.log')
        }
        finally {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'filters directory listings with only an After bound' {
        $tempDir = Join-Path $script:TempRoot "powerclaw-dir-after-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        $olderPath = Join-Path $tempDir 'older.txt'
        $newerPath = Join-Path $tempDir 'newer.txt'

        try {
            Set-Content -LiteralPath $olderPath -Value 'old'
            Set-Content -LiteralPath $newerPath -Value 'new'

            (Get-Item -LiteralPath $olderPath).LastWriteTime = [datetime]'2026-04-01T08:00:00'
            (Get-Item -LiteralPath $newerPath).LastWriteTime = [datetime]'2026-04-04T09:15:00'

            $result = @(Get-DirectoryListing -Path $tempDir -After ([datetime]'2026-04-02T00:00:00') -Limit 10)

            @($result.Name) | Should -Be @('newer.txt')
        }
        finally {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'filters Search-Files results with modified-time bounds after index retrieval' {
        $script:SearchFilesFakeCommand = $null

        Mock New-Object {
            param($TypeName, $ArgumentList)

            $script:SearchFilesFakeCommand = [PSCustomObject]@{
                CommandText = $null
            }

            $connection = [PSCustomObject]@{
                State = [System.Data.ConnectionState]::Closed
            }
            $connection | Add-Member -MemberType ScriptMethod -Name Open -Value { $this.State = [System.Data.ConnectionState]::Open }
            $connection | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.State = [System.Data.ConnectionState]::Closed }
            $connection | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            $connection | Add-Member -MemberType ScriptMethod -Name CreateCommand -Value { return $script:SearchFilesFakeCommand }
            return $connection
        } -ParameterFilter { $TypeName -eq 'System.Data.OleDb.OleDbConnection' }

        Mock New-Object {
            param($TypeName, $ArgumentList)

            $adapter = [PSCustomObject]@{}
            $adapter | Add-Member -MemberType ScriptMethod -Name Fill -Value {
                param($DataSet)

                $table = New-Object System.Data.DataTable
                [void]$table.Columns.Add('SYSTEM.ITEMNAME')
                [void]$table.Columns.Add('SYSTEM.ITEMPATHDISPLAY')
                [void]$table.Columns.Add('SYSTEM.SIZE', [double])
                [void]$table.Columns.Add('SYSTEM.DATEMODIFIED', [datetime])

                foreach ($rowData in @(
                    @{ Name = 'older.log';  Path = 'C:\Temp\older.log';  Size = 10MB; DateModified = [datetime]'2026-04-01T08:00:00' }
                    @{ Name = 'middle.log'; Path = 'C:\Temp\middle.log'; Size = 20MB; DateModified = [datetime]'2026-04-02T12:00:00' }
                    @{ Name = 'newer.log';  Path = 'C:\Temp\newer.log';  Size = 30MB; DateModified = [datetime]'2026-04-03T18:30:00' }
                )) {
                    $row = $table.NewRow()
                    $row['SYSTEM.ITEMNAME'] = $rowData.Name
                    $row['SYSTEM.ITEMPATHDISPLAY'] = $rowData.Path
                    $row['SYSTEM.SIZE'] = [double]$rowData.Size
                    $row['SYSTEM.DATEMODIFIED'] = $rowData.DateModified
                    [void]$table.Rows.Add($row)
                }

                [void]$DataSet.Tables.Add($table)
                return $table.Rows.Count
            }
            $adapter | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            return $adapter
        } -ParameterFilter { $TypeName -eq 'System.Data.OleDb.OleDbDataAdapter' }

        $result = @(Search-Files -Scope 'C:\Temp' -After ([datetime]'2026-04-02T12:00:00') -Before ([datetime]'2026-04-03T18:30:00') -Limit 2 -SortBy DateModified)

        @($result.Name) | Should -Be @('middle.log', 'newer.log')
        $script:SearchFilesFakeCommand.CommandText | Should -Not -Match '\bTOP 2\b'
        $script:SearchFilesFakeCommand.CommandText | Should -Match 'System\.DateModified'
    }

    It 'deletes a literal-path file with wildcard characters in its name' {
        $tempFile = Join-Path $script:TempRoot 'powerclaw pester [literal].txt'
        Set-Content -LiteralPath $tempFile -Value 'x'
        $expectedPath = (Get-Item -LiteralPath $tempFile).FullName

        try {
            $result = Remove-Files -Paths @($tempFile)

            $result.FilesDeleted | Should -Be 1
            $result.Failed.Count | Should -Be 0
            $result.NotFound.Count | Should -Be 0
            $result.Deleted[0].Path | Should -Be $expectedPath
        }
        finally {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks relative paths for Remove-Files' {
        $result = Remove-Files -Paths @('.\example.txt')

        $result.FilesDeleted | Should -Be 0
        $result.Blocked.Count | Should -Be 1
        $result.Blocked[0].Reason | Should -Match 'fully qualified'
    }

    It 'blocks deletion from protected system roots' {
        $protectedFile = Join-Path $env:WINDIR 'win.ini'

        $result = Remove-Files -Paths @($protectedFile) -Permanent:$true

        $result.FilesDeleted | Should -Be 0
        $result.Blocked.Count | Should -Be 1
        $result.Blocked[0].Path | Should -Be $protectedFile
        $result.Blocked[0].Reason | Should -Match 'blocked by policy'
        Test-Path -LiteralPath $protectedFile | Should -BeTrue
    }

    It 'blocks delete batches that exceed the explicit per-call ceiling' {
        $result = Remove-Files -Paths @(
            'C:\temp\a.txt',
            'C:\temp\b.txt',
            'C:\temp\c.txt'
        ) -MaxDeleteCount 2

        $result.FilesDeleted | Should -Be 0
        $result.Blocked.Count | Should -Be 1
        $result.Blocked[0].Reason | Should -Match 'exceeds MaxDeleteCount=2'
    }

    It 'blocks permanent delete requests that include more than one file' {
        $result = Remove-Files -Paths @(
            'C:\temp\a.txt',
            'C:\temp\b.txt'
        ) -Permanent:$true -MaxDeleteCount 2

        $result.FilesDeleted | Should -Be 0
        $result.Blocked.Count | Should -Be 1
        $result.Blocked[0].Reason | Should -Match 'Permanent delete is limited to one file per call'
    }

    It 'classifies browser launch permission failures for Fetch-WebPage clearly' {
        $message = Resolve-ClawWebFetchFailureMessage `
            -Url 'https://news.ycombinator.com' `
            -FailureText 'spawn EPERM' `
            -LaunchAttempts @('Chrome channel', 'Edge channel', 'Bundled Chromium')

        $message | Should -Match 'could not launch a browser'
        $message | Should -Match 'normal local PowerShell session'
        $message | Should -Match 'Chrome channel, Edge channel, Bundled Chromium'
    }

    It 'classifies missing browser runtime failures for Fetch-WebPage clearly' {
        $message = Resolve-ClawWebFetchFailureMessage `
            -Url 'https://example.com' `
            -FailureText "Executable doesn't exist" `
            -LaunchAttempts @('Bundled Chromium')

        $message | Should -Match 'could not find a usable browser runtime'
        $message | Should -Match 'Install-PowerClawWebRuntime\.ps1'
        $message | Should -Match 'Test-PowerClawSetup'
    }

    It 'lists bundled chromium as the final browser launch fallback' {
        $candidates = @(Get-ClawBrowserLaunchCandidates)

        $candidates.Count | Should -BeGreaterThan 0
        $candidates[-1].Label | Should -Be 'Bundled Chromium'
    }
}

Describe 'Registry and schema' {
    It 'emits schemas with additionalProperties disabled' {
        $schema = ConvertTo-ClaudeToolSchema ([PSCustomObject]@{
            Name = 'Get-Test'
            Description = 'test tool'
            Parameters = @(
                [PSCustomObject]@{ Name = 'Path'; Type = 'String'; Required = $true }
            )
        })

        $schema.input_schema.additionalProperties | Should -BeFalse
    }

    It 'keeps Fetch-WebPage opt-in and Search-LocalKnowledge in the default approved tool set' {
        $manifestPath = Join-Path $script:RepoRoot 'tools-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

        'Fetch-WebPage' -in @($manifest.approved_tools) | Should -BeFalse
        'Fetch-WebPage' -in @($manifest.disabled_tools) | Should -BeFalse
        'Get-CleanupSummary' -in @($manifest.approved_tools) | Should -BeTrue
        'Search-LocalKnowledge' -in @($manifest.approved_tools) | Should -BeTrue
    }

    It 'keeps personal tools outside the main portable tool directory' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'tools\Search-MyJoNotes.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'tools\Search-MnVault.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'overlays\personal\tools\Search-MyJoNotes.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'overlays\personal\tools\Search-MnVault.ps1') | Should -BeTrue
    }

    It 'emits date-time schema properties for DateTime parameters' {
        $schema = ConvertTo-ClaudeToolSchema ([PSCustomObject]@{
            Name = 'Get-DateBounded'
            Description = 'date bounded tool'
            Parameters = @(
                [PSCustomObject]@{ Name = 'After'; Type = 'DateTime'; Required = $false },
                [PSCustomObject]@{ Name = 'Before'; Type = 'DateTimeOffset'; Required = $false }
            )
        })

        $schema.input_schema.properties.After.type | Should -Be 'string'
        $schema.input_schema.properties.After.format | Should -Be 'date-time'
        $schema.input_schema.properties.Before.type | Should -Be 'string'
        $schema.input_schema.properties.Before.format | Should -Be 'date-time'
    }
}

Describe 'Overlay install helper' {
    It 'copies overlay tools into a target root and updates the target manifest' {
        $tempRoot = Join-Path $script:TempRoot 'powerclaw-pester-overlay-install'
        $targetRoot = Join-Path $tempRoot 'target'
        $targetTools = Join-Path $targetRoot 'tools'
        $targetManifest = Join-Path $targetRoot 'tools-manifest.json'
        New-Item -ItemType Directory -Path $targetTools -Force | Out-Null
        Set-Content -LiteralPath $targetManifest -Value @'
{
  "approved_tools": ["Get-TopProcesses"],
  "disabled_tools": ["Search-MyJoNotes"]
}
'@

        try {
            & (Join-Path $script:RepoRoot 'Install-PowerClawOverlay.ps1') -OverlayName personal -RepoRoot $script:RepoRoot -TargetRoot $targetRoot

            $manifest = Get-Content -LiteralPath $targetManifest -Raw | ConvertFrom-Json
            Test-Path -LiteralPath (Join-Path $targetTools 'Search-MyJoNotes.ps1') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $targetTools 'Search-MnVault.ps1') | Should -BeTrue
            'Search-MyJoNotes' -in @($manifest.approved_tools) | Should -BeTrue
            'Search-MnVault' -in @($manifest.approved_tools) | Should -BeTrue
            'Search-MyJoNotes' -in @($manifest.disabled_tools) | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'copies the web runtime installer into the installed module tree' {
        $tempRoot = Join-Path $script:TempRoot 'powerclaw-pester-install'
        $moduleRoot = Join-Path $tempRoot 'modules'
        $binRoot = Join-Path $tempRoot 'bin'
        $scriptPath = Join-Path $script:RepoRoot 'Install-PowerClaw.ps1'
        $manifest = Import-PowerShellDataFile -Path (Join-Path $script:RepoRoot 'PowerClaw.psd1')
        $installRoot = Join-Path (Join-Path $moduleRoot 'PowerClaw') ([string]$manifest.ModuleVersion)

        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

        try {
            & $scriptPath -ModuleRoot $moduleRoot -BinRoot $binRoot

            Test-Path -LiteralPath (Join-Path $installRoot 'Install-PowerClawWebRuntime.ps1') | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Providers' {
    It 'stub mode picks Get-CleanupSummary for biggest-files cleanup prompts when available' {
        $result = Send-ClawRequest `
            -Messages @(@{ role = 'user'; content = 'Find the 10 biggest files in Downloads' }) `
            -ToolSchemas @(
                @{ name = 'Get-CleanupSummary' },
                @{ name = 'Search-Files' },
                @{ name = 'Get-TopProcesses' }
            ) `
            -UseStub

        $result.Type | Should -Be 'tool_call'
        $result.ToolName | Should -Be 'Get-CleanupSummary'
        $result.ToolInput.Scope | Should -Match 'Downloads'
        $result.ToolInput.Limit | Should -Be 10
    }

    It 'stub mode prefers Get-SystemTriage for hard-drive health prompts when available' {
        $result = Send-ClawRequest `
            -Messages @(@{ role = 'user'; content = 'What about my hard drive?' }) `
            -ToolSchemas @(
                @{ name = 'Get-SystemTriage' },
                @{ name = 'Get-StorageStatus' }
            ) `
            -UseStub

        $result.Type | Should -Be 'tool_call'
        $result.ToolName | Should -Be 'Get-SystemTriage'
    }

    It 'stub mode picks Fetch-WebPage for URL prompts when the tool is available' {
        $result = Send-ClawRequest `
            -Messages @(@{ role = 'user'; content = 'Summarize https://news.ycombinator.com' }) `
            -ToolSchemas @(
                @{ name = 'Fetch-WebPage' },
                @{ name = 'Read-FileContent' }
            ) `
            -UseStub

        $result.Type | Should -Be 'tool_call'
        $result.ToolName | Should -Be 'Fetch-WebPage'
        $result.ToolInput.Url | Should -Be 'https://news.ycombinator.com'
    }

    It 'stub mode picks Search-LocalKnowledge for notes prompts when the tool is available' {
        $result = Send-ClawRequest `
            -Messages @(@{ role = 'user'; content = 'Search my notes for local setup decisions' }) `
            -ToolSchemas @(
                @{ name = 'Search-LocalKnowledge' },
                @{ name = 'Read-FileContent' }
            ) `
            -UseStub

        $result.Type | Should -Be 'tool_call'
        $result.ToolName | Should -Be 'Search-LocalKnowledge'
        $result.ToolInput.Collection | Should -Be 'all'
    }

    It 'stub mode picks Get-RecentChangesSummary for recent-change prompts when available' {
        $result = Send-ClawRequest `
            -Messages @(@{ role = 'user'; content = 'What changed on this machine in the last 24 hours?' }) `
            -ToolSchemas @(
                @{ name = 'Get-RecentChangesSummary' },
                @{ name = 'Search-Files' }
            ) `
            -UseStub

        $result.Type | Should -Be 'tool_call'
        $result.ToolName | Should -Be 'Get-RecentChangesSummary'
        $result.ToolInput.HoursBack | Should -Be 24
    }

    It 'stub mode turns tool output into a workflow-shaped final answer' {
        $result = Send-ClawRequest `
            -Messages @(
                @{ role = 'user'; content = 'What is eating my CPU?' }
                @{
                    role = 'assistant'
                    content = @(@{
                        type  = 'tool_use'
                        id    = 'toolu_stub'
                        name  = 'Get-TopProcesses'
                        input = @{ SortBy = 'CPU'; Count = 5 }
                    })
                }
                @{
                    role = 'user'
                    content = @(@{
                        type        = 'tool_result'
                        tool_use_id = 'toolu_stub'
                        content     = @'
Name Id CPU MemoryMB
foo 123 99.4 512.0
bar 234 21.5 128.0
'@
                    })
                }
            ) `
            -ToolSchemas @(@{ name = 'Get-TopProcesses' }) `
            -UseStub

        $result.Type | Should -Be 'final_answer'
        $result.Content | Should -Match 'Overall status: resource usage is concentrated'
        $result.Content | Should -Match 'Key finding: the main CPU consumer is highlighted first'
        $result.Content | Should -Match 'foo 123 99.4 512.0'
    }

    It 'stub mode shapes file investigation answers as answer evidence implication' {
        $result = Send-ClawRequest `
            -Messages @(
                @{ role = 'user'; content = 'Read config.json and explain my settings' }
                @{
                    role = 'assistant'
                    content = @(@{
                        type  = 'tool_use'
                        id    = 'toolu_stub_file'
                        name  = 'Read-FileContent'
                        input = @{ Path = 'config.json' }
                    })
                }
                @{
                    role = 'user'
                    content = @(@{
                        type        = 'tool_result'
                        tool_use_id = 'toolu_stub_file'
                        content     = @'
Path       : config.json
LinesShown : 4
Truncated  : False
Content    : provider=openai
             model=gpt-4.1-mini
             api_key_env=OPENAI_API_KEY
'@
                    })
                }
            ) `
            -ToolSchemas @(@{ name = 'Read-FileContent' }) `
            -UseStub

        $result.Type | Should -Be 'final_answer'
        $result.Content | Should -Match 'Answer: this file contains the main settings'
        $result.Content | Should -Match 'Evidence: PowerClaw would pull out the specific settings'
        $result.Content | Should -Match 'Implication: explain what these values mean'
    }

    It 'stub mode shapes webpage investigation answers as answer evidence implication' {
        $result = Send-ClawRequest `
            -Messages @(
                @{ role = 'user'; content = 'Summarize https://example.com' }
                @{
                    role = 'assistant'
                    content = @(@{
                        type  = 'tool_use'
                        id    = 'toolu_stub_web'
                        name  = 'Fetch-WebPage'
                        input = @{ Url = 'https://example.com' }
                    })
                }
                @{
                    role = 'user'
                    content = @(@{
                        type        = 'tool_result'
                        tool_use_id = 'toolu_stub_web'
                        content     = @'
Url        : https://example.com
Title      : Demo Page Summary
Characters : 1240
Truncated  : False
Content    : Top stories focus on browser automation and Windows tooling.
'@
                    })
                }
            ) `
            -ToolSchemas @(@{ name = 'Fetch-WebPage' }) `
            -UseStub

        $result.Type | Should -Be 'final_answer'
        $result.Content | Should -Match 'Answer: PowerClaw would summarize the page contents'
        $result.Content | Should -Match 'Evidence: call out the important topics'
        $result.Content | Should -Match 'Implication: mention why those takeaways matter'
    }

    It 'stub mode previews a multi-step health-check plan chain' {
        $messages = @(
            @{ role = 'user'; content = 'Give me a full system health check' }
            @{
                role = 'assistant'
                content = @(@{
                    type  = 'tool_use'
                    id    = 'toolu_plan_1'
                    name  = 'Get-SystemTriage'
                    input = @{}
                })
            }
            @{
                role = 'user'
                content = @(@{
                    type        = 'tool_result'
                    tool_use_id = 'toolu_plan_1'
                    content     = 'Plan preview only: Get-SystemTriage was not executed.'
                })
            }
        )

        $result = Send-ClawRequest `
            -Messages $messages `
            -ToolSchemas @(
                @{ name = 'Get-SystemTriage' },
                @{ name = 'Get-SystemSummary' },
                @{ name = 'Get-StorageStatus' },
                @{ name = 'Get-NetworkStatus' }
            ) `
            -UseStub

        $result.Type | Should -Be 'tool_call'
        $result.ToolName | Should -Be 'Get-StorageStatus'
    }

    It 'stub mode returns a cleanup plan summary after previewing the chain' {
        $messages = @(
            @{ role = 'user'; content = 'Find the 10 biggest files in Downloads and tell me what I should clean up' }
            @{
                role = 'assistant'
                content = @(@{
                    type  = 'tool_use'
                    id    = 'toolu_plan_1'
                    name  = 'Get-CleanupSummary'
                    input = @{ Scope = 'C:\Users\chris\Downloads'; Limit = 10; MinSizeMB = 50 }
                })
            }
            @{
                role = 'user'
                content = @(@{
                    type        = 'tool_result'
                    tool_use_id = 'toolu_plan_1'
                    content     = 'Plan preview only: Get-CleanupSummary was not executed.'
                })
            }
            @{
                role = 'assistant'
                content = @(@{
                    type  = 'tool_use'
                    id    = 'toolu_plan_2'
                    name  = 'Get-DirectoryListing'
                    input = @{ Path = 'C:\Users\chris\Downloads'; Limit = 25 }
                })
            }
            @{
                role = 'user'
                content = @(@{
                    type        = 'tool_result'
                    tool_use_id = 'toolu_plan_2'
                    content     = 'Plan preview only: Get-DirectoryListing was not executed.'
                })
            }
        )

        $result = Send-ClawRequest `
            -Messages $messages `
            -ToolSchemas @(
                @{ name = 'Get-CleanupSummary' },
                @{ name = 'Get-DirectoryListing' }
            ) `
            -UseStub

        $result.Type | Should -Be 'final_answer'
        $result.Content | Should -Match 'deterministic cleanup summary'
    }

    It 'translates OpenAI requests and parses tool-call responses' {
        $env:POWERCLAW_TEST_OPENAI_KEY = 'test-openai-key'

        Mock Invoke-RestMethod {
            $script:OpenAiCall = @{
                Uri = $Uri
                Body = $Body | ConvertFrom-Json -Depth 20
                Headers = $Headers
            }

            [PSCustomObject]@{
                choices = @(
                    [PSCustomObject]@{
                        finish_reason = 'tool_calls'
                        message = [PSCustomObject]@{
                            tool_calls = @(
                                [PSCustomObject]@{
                                    id = 'call_123'
                                    function = [PSCustomObject]@{
                                        name = 'Get-TopProcesses'
                                        arguments = '{"SortBy":"CPU","Count":5}'
                                    }
                                }
                            )
                        }
                    }
                )
            }
        }

        $result = Send-OpenAiRequest `
            -SystemPrompt 'system prompt' `
            -Messages @(
                @{ role = 'user'; content = 'show me top processes' }
                @{
                    role = 'assistant'
                    content = @(@{
                        type  = 'tool_use'
                        id    = 'toolu_1'
                        name  = 'Get-TopProcesses'
                        input = @{ SortBy = 'Memory'; Count = 3 }
                    })
                }
                @{
                    role = 'user'
                    content = @(@{
                        type        = 'tool_result'
                        tool_use_id = 'toolu_1'
                        content     = 'tool output'
                    })
                }
            ) `
            -ToolSchemas @(
                @{
                    name = 'Get-TopProcesses'
                    description = 'Gets top processes'
                    input_schema = @{
                        type = 'object'
                        properties = @{
                            SortBy = @{ type = 'string' }
                            Count  = @{ type = 'integer' }
                        }
                    }
                }
            ) `
            -Config ([PSCustomObject]@{
                model = 'gpt-test'
                max_tokens = 256
                api_key_env = 'POWERCLAW_TEST_OPENAI_KEY'
            })

        $script:OpenAiCall.Uri | Should -Be 'https://api.openai.com/v1/chat/completions'
        $script:OpenAiCall.Body.messages[0].role | Should -Be 'system'
        $script:OpenAiCall.Body.messages[2].tool_calls[0].function.name | Should -Be 'Get-TopProcesses'
        $script:OpenAiCall.Body.messages[3].role | Should -Be 'tool'
        $result.Type | Should -Be 'tool_call'
        $result.ToolName | Should -Be 'Get-TopProcesses'
        $result.ToolInput.Count | Should -Be 5
    }

    It 'translates OpenAI tool-result turns and parses the follow-up final answer' {
        $env:POWERCLAW_TEST_OPENAI_KEY = 'test-openai-key'

        Mock Invoke-RestMethod {
            $script:OpenAiToolResultCall = @{
                Uri = $Uri
                Body = $Body | ConvertFrom-Json -Depth 20
                Headers = $Headers
            }

            [PSCustomObject]@{
                choices = @(
                    [PSCustomObject]@{
                        finish_reason = 'stop'
                        message = [PSCustomObject]@{
                            content = 'POWERCLAW_TOOL_ROUNDTRIP_OK'
                        }
                    }
                )
            }
        }

        $result = Send-OpenAiRequest `
            -SystemPrompt 'system prompt' `
            -Messages @(
                @{ role = 'user'; content = 'Use the tool and then summarize the result.' }
                @{
                    role = 'assistant'
                    content = @(@{
                        type  = 'tool_use'
                        id    = 'toolu_roundtrip'
                        name  = 'Get-SmokeStatus'
                        input = @{ Label = 'POWERCLAW_SMOKE_TOOL' }
                    })
                }
                @{
                    role = 'user'
                    content = @(@{
                        type        = 'tool_result'
                        tool_use_id = 'toolu_roundtrip'
                        content     = 'Tool returned POWERCLAW_SMOKE_TOOL.'
                    })
                }
            ) `
            -ToolSchemas @(
                @{
                    name = 'Get-SmokeStatus'
                    description = 'Returns the smoke label for verification.'
                    input_schema = @{
                        type = 'object'
                        properties = @{
                            Label = @{ type = 'string' }
                        }
                        required = @('Label')
                        additionalProperties = $false
                    }
                }
            ) `
            -Config ([PSCustomObject]@{
                model = 'gpt-test'
                max_tokens = 256
                api_key_env = 'POWERCLAW_TEST_OPENAI_KEY'
            })

        $script:OpenAiToolResultCall.Uri | Should -Be 'https://api.openai.com/v1/chat/completions'
        $script:OpenAiToolResultCall.Body.messages[0].role | Should -Be 'system'
        $script:OpenAiToolResultCall.Body.messages[2].tool_calls[0].id | Should -Be 'toolu_roundtrip'
        $script:OpenAiToolResultCall.Body.messages[3].role | Should -Be 'tool'
        $script:OpenAiToolResultCall.Body.messages[3].tool_call_id | Should -Be 'toolu_roundtrip'
        $script:OpenAiToolResultCall.Body.messages[3].content | Should -Be 'Tool returned POWERCLAW_SMOKE_TOOL.'
        $result.Type | Should -Be 'final_answer'
        $result.Content | Should -Be 'POWERCLAW_TOOL_ROUNDTRIP_OK'
    }

    It 'builds Claude payloads and converts tool_use input to a hashtable' {
        $env:POWERCLAW_TEST_CLAUDE_KEY = 'test-claude-key'

        Mock Invoke-RestMethod {
            $script:ClaudeCall = @{
                Uri = $Uri
                Body = $Body | ConvertFrom-Json -Depth 20
                Headers = $Headers
            }

            [PSCustomObject]@{
                stop_reason = 'tool_use'
                content = @(
                    [PSCustomObject]@{
                        type  = 'tool_use'
                        id    = 'toolu_abc'
                        name  = 'Search-Files'
                        input = [PSCustomObject]@{
                            FileName = '*.log'
                            Limit    = 10
                        }
                    }
                )
            }
        }

        $result = Send-ClaudeRequest `
            -SystemPrompt 'system prompt' `
            -Messages @(@{ role = 'user'; content = 'find logs' }) `
            -ToolSchemas @(
                @{
                    name = 'Search-Files'
                    description = 'Searches files'
                    input_schema = @{
                        type = 'object'
                        properties = @{
                            FileName = @{ type = 'string' }
                            Limit    = @{ type = 'integer' }
                        }
                    }
                }
            ) `
            -Config ([PSCustomObject]@{
                model = 'claude-test'
                max_tokens = 256
                api_key_env = 'POWERCLAW_TEST_CLAUDE_KEY'
            })

        $script:ClaudeCall.Uri | Should -Be 'https://api.anthropic.com/v1/messages'
        $script:ClaudeCall.Body.system | Should -Be 'system prompt'
        $script:ClaudeCall.Body.tools[0].name | Should -Be 'Search-Files'
        $result.Type | Should -Be 'tool_call'
        $result.ToolName | Should -Be 'Search-Files'
        $result.ToolInput.Limit | Should -Be 10
    }

    It 'passes Claude tool-result turns through and parses the follow-up final answer' {
        $env:POWERCLAW_TEST_CLAUDE_KEY = 'test-claude-key'

        Mock Invoke-RestMethod {
            $script:ClaudeToolResultCall = @{
                Uri = $Uri
                Body = $Body | ConvertFrom-Json -Depth 20
                Headers = $Headers
            }

            [PSCustomObject]@{
                stop_reason = 'end_turn'
                content = @(
                    [PSCustomObject]@{
                        type = 'text'
                        text = 'POWERCLAW_TOOL_ROUNDTRIP_OK'
                    }
                )
            }
        }

        $result = Send-ClaudeRequest `
            -SystemPrompt 'system prompt' `
            -Messages @(
                @{ role = 'user'; content = 'Use the tool and then summarize the result.' }
                @{
                    role = 'assistant'
                    content = @(@{
                        type  = 'tool_use'
                        id    = 'toolu_roundtrip'
                        name  = 'Get-SmokeStatus'
                        input = @{ Label = 'POWERCLAW_SMOKE_TOOL' }
                    })
                }
                @{
                    role = 'user'
                    content = @(@{
                        type        = 'tool_result'
                        tool_use_id = 'toolu_roundtrip'
                        content     = 'Tool returned POWERCLAW_SMOKE_TOOL.'
                    })
                }
            ) `
            -ToolSchemas @(
                @{
                    name = 'Get-SmokeStatus'
                    description = 'Returns the smoke label for verification.'
                    input_schema = @{
                        type = 'object'
                        properties = @{
                            Label = @{ type = 'string' }
                        }
                        required = @('Label')
                        additionalProperties = $false
                    }
                }
            ) `
            -Config ([PSCustomObject]@{
                model = 'claude-test'
                max_tokens = 256
                api_key_env = 'POWERCLAW_TEST_CLAUDE_KEY'
            })

        $script:ClaudeToolResultCall.Uri | Should -Be 'https://api.anthropic.com/v1/messages'
        $script:ClaudeToolResultCall.Body.system | Should -Be 'system prompt'
        $script:ClaudeToolResultCall.Body.messages[1].content[0].id | Should -Be 'toolu_roundtrip'
        $script:ClaudeToolResultCall.Body.messages[2].content[0].type | Should -Be 'tool_result'
        $script:ClaudeToolResultCall.Body.messages[2].content[0].tool_use_id | Should -Be 'toolu_roundtrip'
        $script:ClaudeToolResultCall.Body.messages[2].content[0].content | Should -Be 'Tool returned POWERCLAW_SMOKE_TOOL.'
        $result.Type | Should -Be 'final_answer'
        $result.Content | Should -Be 'POWERCLAW_TOOL_ROUNDTRIP_OK'
    }

    It 'surfaces OpenAI insufficient quota distinctly from generic rate limits' {
        $message = Resolve-OpenAiApiErrorMessage `
            -Status 429 `
            -Detail '{"error":{"message":"You exceeded your current quota.","type":"insufficient_quota","code":"insufficient_quota"}}' `
            -ApiKeyEnv 'OPENAI_API_KEY'

        $message | Should -Match 'quota exhausted or billing is not available'
        $message | Should -Match 'You exceeded your current quota'
    }

    It 'includes OpenAI rate-limit detail when available' {
        $message = Resolve-OpenAiApiErrorMessage `
            -Status 429 `
            -Detail '{"error":{"message":"Please retry after 10s.","type":"rate_limit_exceeded","code":"rate_limit_exceeded"}}' `
            -ApiKeyEnv 'OPENAI_API_KEY'

        $message | Should -Match 'Rate limited by OpenAI'
        $message | Should -Match 'Please retry after 10s'
    }

    It 'includes Claude overload detail when available' {
        $message = Resolve-ClaudeApiErrorMessage `
            -Status 529 `
            -Detail '{"error":{"message":"Overloaded right now.","type":"overloaded_error"}}' `
            -ApiKeyEnv 'CLAUDE_API_KEY'

        $message | Should -Match 'Claude API is overloaded'
        $message | Should -Match 'Overloaded right now'
    }
}

Describe 'System triage producer' {
    It 'runs the allowed collectors in spec order and returns a triage document' {
        $script:Calls = [System.Collections.Generic.List[string]]::new()

        Mock Get-SystemSummary {
            $script:Calls.Add('Get-SystemSummary') | Out-Null
            [PSCustomObject]@{
                MachineName = 'ws-01'
                CPULoadPct = 18
                RAMUsedPct = 63
                Uptime = '2d 0h 0m'
            }
        }
        Mock Get-TopProcesses {
            param([string]$SortBy, [int]$Count)
            $script:Calls.Add("Get-TopProcesses:$SortBy") | Out-Null
            if ($SortBy -eq 'Memory') {
                return @([PSCustomObject]@{ Name = 'Code'; CPU = 22.4; MemoryMB = 842.0 })
            }
            @([PSCustomObject]@{ Name = 'Code'; CPU = 22.4; MemoryMB = 842.0 })
        }
        Mock Get-ServiceStatus {
            $script:Calls.Add('Get-ServiceStatus') | Out-Null
            @([PSCustomObject]@{ Name = 'Spooler'; Status = 'Running'; StartType = 'Automatic' })
        }
        Mock Get-EventLogEntries {
            $script:Calls.Add('Get-EventLogEntries') | Out-Null
            @([PSCustomObject]@{ Source = 'Service Control Manager'; Level = 'Information' })
        }
        Mock Get-StorageStatus {
            $script:Calls.Add('Get-StorageStatus') | Out-Null
            @([PSCustomObject]@{ Drive = 'C'; FreeGB = 120.0; PercentFull = 58.0 })
        }

        $doc = Invoke-SystemTriage

        @($script:Calls) | Should -Be @(
            'Get-SystemSummary',
            'Get-TopProcesses:CPU',
            'Get-TopProcesses:Memory',
            'Get-ServiceStatus',
            'Get-EventLogEntries',
            'Get-StorageStatus'
        )
        $doc.kind | Should -Be 'system_triage'
        $doc.summary.status | Should -Be 'ok'
        @($doc.sources | ForEach-Object id) | Should -Be @(
            'src_system',
            'src_processes',
            'src_services',
            'src_events',
            'src_storage'
        )
    }

    It 'continues after collector failures and omits failed sources' {
        Mock Get-SystemSummary {
            [PSCustomObject]@{
                MachineName = 'ws-01'
                CPULoadPct = 18
                RAMUsedPct = 63
                Uptime = '2d 0h 0m'
            }
        }
        Mock Get-TopProcesses { throw 'process collector failed' }
        Mock Get-ServiceStatus { throw 'service collector failed' }
        Mock Get-EventLogEntries { @() }
        Mock Get-StorageStatus { @([PSCustomObject]@{ Drive = 'C'; FreeGB = 120.0; PercentFull = 58.0 }) }

        $doc = Invoke-SystemTriage

        $doc.kind | Should -Be 'system_triage'
        $doc.summary.status | Should -Be 'ok'
        @($doc.sources | ForEach-Object id) | Should -Be @(
            'src_system',
            'src_events',
            'src_storage'
        )
        $doc.findings.Count | Should -Be 0
    }

    It 'can emit JSON directly from the collector wrapper' {
        Mock Get-SystemSummary {
            [PSCustomObject]@{
                MachineName = 'ws-01'
                CPULoadPct = 18
                RAMUsedPct = 63
                Uptime = '2d 0h 0m'
            }
        }
        Mock Get-TopProcesses { @([PSCustomObject]@{ Name = 'Code'; CPU = 22.4; MemoryMB = 842.0 }) }
        Mock Get-ServiceStatus { @() }
        Mock Get-EventLogEntries { @() }
        Mock Get-StorageStatus { @([PSCustomObject]@{ Drive = 'C'; FreeGB = 120.0; PercentFull = 58.0 }) }

        $json = Invoke-SystemTriage -AsJson
        $parsed = $json | ConvertFrom-Json

        $parsed.kind | Should -Be 'system_triage'
        $parsed.window_minutes | Should -Be 60
    }

    It 'normalizes current collector outputs into the v1 producer input shape' {
        $normalized = ConvertTo-SystemTriageNormalizedInput `
            -SystemSummary ([PSCustomObject]@{
                System = [PSCustomObject]@{
                    MachineName = 'ws-01.contoso.local'
                    CPULoadPct = 71.2
                    RAMUsedPct = 84.1
                    Uptime = '4d 6h 30m'
                }
            }) `
            -TopCpuProcesses @([PSCustomObject]@{ Name = 'Code'; CPU = 22.4 }) `
            -TopMemoryProcesses @([PSCustomObject]@{ Name = 'Code'; MemoryMB = 842.0 }) `
            -ServiceStatus @([PSCustomObject]@{ Name = 'Spooler'; Status = 'Stopped'; StartType = 'Automatic' }) `
            -EventLogEntries @(
                [PSCustomObject]@{ Source = 'Service Control Manager'; Level = 'Error' },
                [PSCustomObject]@{ Source = 'Service Control Manager'; Level = 'Warning' }
            ) `
            -StorageStatus ([PSCustomObject]@{
                Drives = @([PSCustomObject]@{ Drive = 'C'; FreeGB = 48.2; PercentFull = 87.6 })
            }) `
            -CapturedAt ([datetimeoffset]'2026-04-04T18:05:00-05:00')

        $normalized.host | Should -Be 'ws-01'
        $normalized.system.cpu_pct | Should -Be 71.2
        $normalized.system.memory_pct | Should -Be 84.1
        $normalized.system.uptime_hours | Should -Be 102.5
        $normalized.top_processes.cpu.name | Should -Be 'Code'
        $normalized.top_processes.memory.mem_mb | Should -Be 842
        $normalized.services[0].startup | Should -Be 'automatic'
        $normalized.services[0].recent_failure_signal | Should -BeTrue
        $normalized.event_sources[0].warning_error_count | Should -Be 2
        $normalized.volumes[0].free_pct | Should -Be 12.4
    }

    It 'emits a healthy v1 document with no findings when inputs are normal' {
        $doc = New-SystemTriageDocument -NormalizedInput ([PSCustomObject]@{
            host = 'ws-01'
            captured_at = '2026-04-04T18:05:00-05:00'
            system = [PSCustomObject]@{ cpu_pct = 18; memory_pct = 63; uptime_hours = 48 }
            top_processes = [PSCustomObject]@{
                cpu = [PSCustomObject]@{ name = 'Code'; cpu_pct = 9.4 }
                memory = [PSCustomObject]@{ name = 'Code'; mem_mb = 842 }
            }
            volumes = @([PSCustomObject]@{ name = 'C'; free_pct = 42.0; free_gb = 120.0; kind = 'fixed'; is_system = $true })
            services = @([PSCustomObject]@{ name = 'Spooler'; state = 'running'; startup = 'automatic'; recent_failure_signal = $false; failure_count = 0 })
            event_sources = @([PSCustomObject]@{ source = 'Service Control Manager'; warning_error_count = 1; error_count = 0 })
        })

        $doc.kind | Should -Be 'system_triage'
        $doc.summary.status | Should -Be 'ok'
        $doc.summary.score | Should -Be 0
        $doc.findings.Count | Should -Be 0
        $doc.actions.Count | Should -Be 0
        $doc.sources.Count | Should -Be 5
        $doc.summary.headline | Should -Match 'No abnormal system-health signals'
    }

    It 'reduces multiple disk candidates to the most severe volume and emits the matching action' {
        $doc = New-SystemTriageDocument -NormalizedInput ([PSCustomObject]@{
            host = 'ws-01'
            captured_at = '2026-04-04T18:05:00-05:00'
            system = [PSCustomObject]@{ cpu_pct = 12; memory_pct = 44; uptime_hours = 48 }
            top_processes = [PSCustomObject]@{ cpu = $null; memory = $null }
            volumes = @(
                [PSCustomObject]@{ name = 'D'; free_pct = 6.5; free_gb = 5.0; kind = 'fixed'; is_system = $false },
                [PSCustomObject]@{ name = 'C'; free_pct = 6.5; free_gb = 10.0; kind = 'fixed'; is_system = $true },
                [PSCustomObject]@{ name = 'E'; free_pct = 12.0; free_gb = 100.0; kind = 'fixed'; is_system = $false }
            )
            services = @()
            event_sources = @()
        })

        $doc.findings.Count | Should -Be 1
        $doc.findings[0].id | Should -Be 'low_disk:d'
        $doc.findings[0].severity | Should -Be 'critical'
        $doc.actions[0].id | Should -Be 'inspect_volume_D'
        $doc.summary.status | Should -Be 'critical'
        $doc.summary.score | Should -Be 40
    }

    It 'flags a getting-tight drive as low_disk warning before the old threshold' {
        $doc = New-SystemTriageDocument -NormalizedInput ([PSCustomObject]@{
            host = 'ws-01'
            captured_at = '2026-04-04T18:05:00-05:00'
            system = [PSCustomObject]@{ cpu_pct = 12; memory_pct = 44; uptime_hours = 48 }
            top_processes = [PSCustomObject]@{ cpu = $null; memory = $null }
            volumes = @([PSCustomObject]@{ name = 'C'; free_pct = 16.3; free_gb = 38.8; kind = 'fixed'; is_system = $true })
            services = @()
            event_sources = @()
        })

        $doc.findings.Count | Should -Be 1
        $doc.findings[0].id | Should -Be 'low_disk:c'
        $doc.findings[0].severity | Should -Be 'warning'
        $doc.summary.status | Should -Be 'warning'
        $doc.summary.score | Should -Be 20
    }

    It 'rolls up multiple unstable allowlisted services into one critical escalation finding' {
        $doc = New-SystemTriageDocument -NormalizedInput ([PSCustomObject]@{
            host = 'ws-01'
            captured_at = '2026-04-04T18:05:00-05:00'
            system = [PSCustomObject]@{ cpu_pct = 22; memory_pct = 56; uptime_hours = 12 }
            top_processes = [PSCustomObject]@{ cpu = $null; memory = $null }
            volumes = @()
            services = @(
                [PSCustomObject]@{ name = 'Spooler'; state = 'stopped'; startup = 'automatic'; recent_failure_signal = $true; failure_count = 1 },
                [PSCustomObject]@{ name = 'Dnscache'; state = 'running'; startup = 'automatic'; recent_failure_signal = $true; failure_count = 2 },
                [PSCustomObject]@{ name = 'BITS'; state = 'stopped'; startup = 'automatic'; recent_failure_signal = $true; failure_count = 4 }
            )
            event_sources = @([PSCustomObject]@{ source = 'Service Control Manager'; warning_error_count = 4; error_count = 2 })
        })

        $doc.findings.Count | Should -Be 1
        $doc.findings[0].id | Should -Be 'unstable_service:multiple'
        $doc.findings[0].severity | Should -Be 'critical'
        $doc.findings[0].evidence[1] | Should -Match 'Dnscache, Spooler'
        $doc.actions[0].kind | Should -Be 'escalate'
        $doc.actions[0].id | Should -Be 'escalate_service_instability'
        $doc.actions[0].reason_code | Should -Be 'service_instability_escalation'
    }

    It 'derives findings actions and headline deterministically for a mixed abnormal case' {
        $doc = New-SystemTriageDocument -NormalizedInput ([PSCustomObject]@{
            host = 'ws-01'
            captured_at = '2026-04-04T18:05:00-05:00'
            system = [PSCustomObject]@{ cpu_pct = 73; memory_pct = 87; uptime_hours = 800 }
            top_processes = [PSCustomObject]@{
                cpu = [PSCustomObject]@{ name = 'Code'; cpu_pct = 22.4 }
                memory = [PSCustomObject]@{ name = 'Code'; mem_mb = 842 }
            }
            volumes = @([PSCustomObject]@{ name = 'C'; free_pct = 14.2; free_gb = 48.2; kind = 'fixed'; is_system = $true })
            services = @([PSCustomObject]@{ name = 'Spooler'; state = 'running'; startup = 'automatic'; recent_failure_signal = $true; failure_count = 1 })
            event_sources = @([PSCustomObject]@{ source = 'Service Control Manager'; warning_error_count = 6; error_count = 4 })
        })

        @($doc.findings | ForEach-Object id) | Should -Be @(
            'low_disk:c',
            'high_memory:global',
            'high_cpu:global',
            'abnormal_uptime_signal:global',
            'unstable_service:spooler',
            'repeated_system_errors:service_control_manager'
        )
        @($doc.actions | ForEach-Object id) | Should -Be @(
            'inspect_volume_C',
            'inspect_memory_top_processes',
            'inspect_cpu_processes',
            'monitor_uptime_context',
            'confirm_spooler_stability'
        )
        @($doc.actions | ForEach-Object reason_code) | Should -Be @(
            'volume_consumers_review',
            'memory_consumers_review',
            'cpu_consumers_review',
            'uptime_monitoring',
            'service_instability_confirmation'
        )
        $doc.summary.status | Should -Be 'warning'
        $doc.summary.score | Should -Be 100
        $doc.summary.headline | Should -Be 'Disk free space is low on C and Memory usage is elevated'
        (Test-SystemTriageDocument -Document $doc).IsValid | Should -BeTrue
    }

    It 'rejects producer-invalid documents that break cross-field invariants' {
        $invalid = [PSCustomObject]@{
            schema_version = '1.0'
            kind = 'system_triage'
            host = 'ws-01'
            captured_at = '2026-04-04T18:05:00-05:00'
            window_minutes = 60
            summary = [PSCustomObject]@{ status = 'ok'; score = 0; headline = 'bad' }
            findings = @(
                [PSCustomObject]@{
                    id = 'high_memory:global'
                    type = 'high_memory'
                    severity = 'warning'
                    category = 'memory'
                    title = 'Memory usage is elevated'
                    reason = 'Current memory usage is above the warning threshold'
                    evidence = @('Memory in use: 87%')
                    confidence = 0.95
                    source_refs = @('src_missing')
                }
            )
            actions = @(
                [PSCustomObject]@{
                    id = 'inspect_memory_top_processes'
                    priority = 1
                    kind = 'inspect'
                    target = 'processes'
                    reason_code = 'memory_consumers_review'
                    reason = 'Review the top memory consumers to identify avoidable pressure'
                    related_finding_ids = @('high_memory:other')
                }
            )
            sources = @()
        }

        $validation = Test-SystemTriageDocument -Document $invalid
        $validation.IsValid | Should -BeFalse
        @($validation.Errors) -join ' ' | Should -Match 'source ref does not resolve'
        @($validation.Errors) -join ' ' | Should -Match 'related finding id does not resolve'
        @($validation.Errors) -join ' ' | Should -Match 'Summary status mismatch'
        @($validation.Errors) -join ' ' | Should -Match 'Summary score mismatch'
    }

    It 'rejects producer-invalid triage documents with ordering mapping and type-mapping mismatches' {
        $invalid = [PSCustomObject]@{
            schema_version = '1.0'
            kind = 'system_triage'
            host = 'ws-01'
            captured_at = '2026-04-04T18:05:00-05:00'
            window_minutes = 60
            summary = [PSCustomObject]@{ status = 'warning'; score = 20; headline = 'bad' }
            findings = @(
                [PSCustomObject]@{
                    id = 'abnormal_uptime_signal:global'
                    type = 'abnormal_uptime_signal'
                    severity = 'info'
                    category = 'uptime'
                    title = 'System uptime may explain current conditions'
                    reason = 'The system restarted recently and some current signals may be post-boot effects'
                    evidence = @('Current uptime: 1.2 hours')
                    confidence = 0.90
                    source_refs = @('src_system')
                },
                [PSCustomObject]@{
                    id = 'high_cpu:not_global'
                    type = 'high_cpu'
                    severity = 'warning'
                    category = 'memory'
                    title = 'CPU usage is elevated'
                    reason = 'Current CPU usage is above the warning threshold'
                    evidence = @('CPU in use: 73%')
                    confidence = 0.95
                    source_refs = @('src_system')
                }
            )
            actions = @(
                [PSCustomObject]@{
                    id = 'inspect_cpu_processes'
                    priority = 2
                    kind = 'inspect'
                    target = 'processes'
                    reason_code = 'cpu_consumers_review'
                    reason = 'Review the top CPU consumers to identify avoidable load'
                    related_finding_ids = @('high_cpu:not_global')
                },
                [PSCustomObject]@{
                    id = 'monitor_uptime_context'
                    priority = 1
                    kind = 'monitor'
                    target = 'uptime'
                    reason_code = 'uptime_monitoring'
                    reason = 'Track whether current signals change as uptime normalizes'
                    related_finding_ids = @('abnormal_uptime_signal:global')
                }
            )
            sources = @(
                [PSCustomObject]@{
                    id = 'src_system'
                    tool = 'Get-SystemSummary'
                    captured_at = '2026-04-04T18:05:00-05:00'
                    scope = 'wrong_scope'
                }
            )
        }

        $validation = Test-SystemTriageDocument -Document $invalid
        $validation.IsValid | Should -BeFalse
        @($validation.Errors) -join ' ' | Should -Match 'Findings are not sorted in deterministic v1 order'
        @($validation.Errors) -join ' ' | Should -Match 'Action priorities must be contiguous starting at 1'
        @($validation.Errors) -join ' ' | Should -Match 'Source scope mismatch'
        @($validation.Errors) -join ' ' | Should -Match 'high_cpu category mismatch'
        @($validation.Errors) -join ' ' | Should -Match 'high_cpu id mismatch'
    }

    It 'rejects abnormal_uptime_signal when it appears without another finding' {
        $invalid = [PSCustomObject]@{
            schema_version = '1.0'
            kind = 'system_triage'
            host = 'ws-01'
            captured_at = '2026-04-04T18:05:00-05:00'
            window_minutes = 60
            summary = [PSCustomObject]@{ status = 'info'; score = 0; headline = 'bad' }
            findings = @(
                [PSCustomObject]@{
                    id = 'abnormal_uptime_signal:global'
                    type = 'abnormal_uptime_signal'
                    severity = 'info'
                    category = 'uptime'
                    title = 'System uptime may explain current conditions'
                    reason = 'The system restarted recently and some current signals may be post-boot effects'
                    evidence = @('Current uptime: 1.2 hours')
                    confidence = 0.90
                    source_refs = @('src_system')
                }
            )
            actions = @(
                [PSCustomObject]@{
                    id = 'monitor_uptime_context'
                    priority = 1
                    kind = 'monitor'
                    target = 'uptime'
                    reason_code = 'uptime_monitoring'
                    reason = 'Track whether current signals change as uptime normalizes'
                    related_finding_ids = @('abnormal_uptime_signal:global')
                }
            )
            sources = @(
                [PSCustomObject]@{
                    id = 'src_system'
                    tool = 'Get-SystemSummary'
                    captured_at = '2026-04-04T18:05:00-05:00'
                    scope = 'local_host'
                }
            )
        }

        $validation = Test-SystemTriageDocument -Document $invalid
        $validation.IsValid | Should -BeFalse
        @($validation.Errors) -join ' ' | Should -Match 'abnormal_uptime_signal must not appear without another finding'
    }

    It 'rejects system triage actions whose reason_code drifts from the canonical template' {
        $invalid = [PSCustomObject]@{
            schema_version = '1.0'
            kind = 'system_triage'
            host = 'ws-01'
            captured_at = '2026-04-04T18:05:00-05:00'
            window_minutes = 60
            summary = [PSCustomObject]@{ status = 'warning'; score = 20; headline = 'CPU usage is elevated' }
            findings = @(
                [PSCustomObject]@{
                    id = 'high_cpu:global'
                    type = 'high_cpu'
                    severity = 'warning'
                    category = 'cpu'
                    title = 'CPU usage is elevated'
                    reason = 'Current CPU usage is above the warning threshold'
                    evidence = @('CPU in use: 73%')
                    confidence = 0.95
                    source_refs = @('src_system')
                }
            )
            actions = @(
                [PSCustomObject]@{
                    id = 'inspect_cpu_processes'
                    priority = 1
                    kind = 'inspect'
                    target = 'processes'
                    reason_code = 'memory_consumers_review'
                    reason = 'Review the top CPU consumers to identify avoidable load'
                    related_finding_ids = @('high_cpu:global')
                }
            )
            sources = @(
                [PSCustomObject]@{
                    id = 'src_system'
                    tool = 'Get-SystemSummary'
                    captured_at = '2026-04-04T18:05:00-05:00'
                    scope = 'local_host'
                }
            )
        }

        $validation = Test-SystemTriageDocument -Document $invalid
        $validation.IsValid | Should -BeFalse
        @($validation.Errors) -join ' ' | Should -Match 'Action reason_code mismatch'
    }
}

Describe 'Cleanup summary producer' {
    It 'runs the bounded cleanup collector and returns a cleanup summary document' {
        Mock Search-Files {
            @(
                [PSCustomObject]@{
                    Name = 'debug.log'
                    Path = 'C:\Users\chris\Downloads\debug.log'
                    SizeMB = 40.2
                    DateModified = [datetimeoffset]'2026-04-03T10:15:00-05:00'
                }
                [PSCustomObject]@{
                    Name = 'driver-pack.exe'
                    Path = 'C:\Users\chris\Downloads\driver-pack.exe'
                    SizeMB = 812.1
                    DateModified = [datetimeoffset]'2026-02-11T09:00:00-05:00'
                }
            )
        }

        $doc = Invoke-CleanupSummary -Scope 'C:\Users\chris\Downloads' -Limit 10 -MinSizeMB 25

        $doc.kind | Should -Be 'cleanup_summary'
        $doc.summary.status | Should -Be 'actionable'
        $doc.summary.execution_allowed_count | Should -Be 1
        $doc.candidates[0].category | Should -Be 'logs'
        $doc.candidates[0].state | Should -Be 'execution_allowed'
        $doc.candidates[0].state_reason | Should -Be 'low_risk_remnant'
        $doc.recommended_order[0] | Should -Be $doc.candidates[0].id
        $doc.next_action.policy_reason | Should -Be 'low_risk_candidates_available_after_confirmation'
        $doc.sources[0].tool | Should -Be 'Search-Files'
    }

    It 'can emit JSON directly from the cleanup collector wrapper' {
        Mock Search-Files {
            @([PSCustomObject]@{
                Name = 'debug.log'
                Path = 'C:\Users\chris\Downloads\debug.log'
                SizeMB = 40.2
                DateModified = [datetimeoffset]'2026-04-03T10:15:00-05:00'
            })
        }

        $json = Invoke-CleanupSummary -AsJson
        $parsed = $json | ConvertFrom-Json

        $parsed.kind | Should -Be 'cleanup_summary'
        $parsed.summary.status | Should -Be 'actionable'
    }

    It 'normalizes cleanup search results into the v1 producer input shape' {
        $normalized = ConvertTo-CleanupSummaryNormalizedInput `
            -SearchResults @(
                [PSCustomObject]@{
                    Name = 'debug.log'
                    Path = 'C:\Users\chris\Downloads\debug.log'
                    SizeMB = 40.2
                    DateModified = [datetimeoffset]'2026-04-03T10:15:00-05:00'
                }
            ) `
            -Scope 'C:\Users\chris\Downloads' `
            -CapturedAt ([datetimeoffset]'2026-04-04T18:05:00-05:00')

        $normalized.scope | Should -Be 'C:\Users\chris\Downloads'
        $normalized.candidates[0].name | Should -Be 'debug.log'
        $normalized.candidates[0].size_mb | Should -Be 40.2
        $normalized.candidates[0].modified_at | Should -Be '2026-04-03T10:15:00.0000000-05:00'
    }

    It 'emits a review-only summary when only higher-risk cleanup candidates exist' {
        $doc = New-CleanupSummaryDocument -NormalizedInput ([PSCustomObject]@{
            scope = 'C:\Users\chris\Downloads'
            captured_at = '2026-04-04T18:05:00-05:00'
            candidates = @(
                [PSCustomObject]@{
                    name = 'obs-recording.mp4'
                    path = 'C:\Users\chris\Downloads\obs-recording.mp4'
                    size_mb = 2144.8
                    modified_at = '2026-04-02T12:00:00-05:00'
                },
                [PSCustomObject]@{
                    name = 'windows-iso-backup.zip'
                    path = 'C:\Users\chris\Downloads\windows-iso-backup.zip'
                    size_mb = 5820.4
                    modified_at = '2026-03-28T09:30:00-05:00'
                }
            )
        })

        $doc.summary.status | Should -Be 'review_only'
        $doc.summary.execution_allowed_count | Should -Be 0
        @($doc.candidates | ForEach-Object state) | Should -Be @('review_only', 'review_only')
        @($doc.candidates | ForEach-Object state_reason) | Should -Be @('archive_requires_review', 'media_requires_review')
        $doc.next_action.kind | Should -Be 'review_candidates'
        $doc.next_action.policy_reason | Should -Be 'specific_user_reference_required'
        (Test-CleanupSummaryDocument -Document $doc).IsValid | Should -BeTrue
    }

    It 'rejects producer-invalid cleanup documents that break cross-field invariants' {
        $invalid = [PSCustomObject]@{
            schema_version = '1.0'
            kind = 'cleanup_summary'
            scope = 'C:\Users\chris\Downloads'
            captured_at = '2026-04-04T18:05:00-05:00'
            summary = [PSCustomObject]@{
                status = 'actionable'
                headline = 'bad'
                candidate_count = 2
                execution_allowed_count = 1
            }
            candidates = @(
                [PSCustomObject]@{
                    id = 'candidate:debug_log'
                    name = 'debug.log'
                    path = 'C:\Users\chris\Downloads\debug.log'
                    category = 'logs'
                    state = 'execution_allowed'
                    state_reason = 'media_requires_review'
                    rank = 1
                    size_mb = 40.2
                    modified_at = '2026-04-03T10:15:00-05:00'
                    rationale = 'ok'
                    evidence = @('Path: C:\Users\chris\Downloads\debug.log')
                    source_refs = @('src_search')
                }
            )
            recommended_order = @('candidate:missing')
            next_action = [PSCustomObject]@{
                kind = 'confirm_delete'
                policy_reason = 'specific_user_reference_required'
                reason = 'ok'
            }
            sources = @(
                [PSCustomObject]@{
                    id = 'src_search'
                    tool = 'Search-Files'
                    captured_at = '2026-04-04T18:05:00-05:00'
                    scope = 'C:\Users\chris\Downloads'
                }
            )
        }

        $validation = Test-CleanupSummaryDocument -Document $invalid
        $validation.IsValid | Should -BeFalse
        @($validation.Errors) -join ' ' | Should -Match 'Recommended order id does not resolve'
        @($validation.Errors) -join ' ' | Should -Match 'Summary candidate_count mismatch'
        @($validation.Errors) -join ' ' | Should -Match 'Candidate state_reason mismatch'
        @($validation.Errors) -join ' ' | Should -Match 'Next action policy_reason mismatch'
    }
}

Describe 'Recent changes summary producer' {
    It 'reduces recent files and recent events into one bounded summary document' {
        Mock Search-Files {
            @(
                [PSCustomObject]@{
                    Name = 'report.txt'
                    Path = 'C:\Users\chris\Desktop\report.txt'
                    SizeMB = 1.2
                    DateModified = [datetimeoffset]'2026-04-04T08:15:00-05:00'
                }
                [PSCustomObject]@{
                    Name = 'notes.md'
                    Path = 'C:\Users\chris\Desktop\notes.md'
                    SizeMB = 0.1
                    DateModified = [datetimeoffset]'2026-04-04T07:55:00-05:00'
                }
            )
        }

        Mock Get-EventLogEntries {
            @(
                [PSCustomObject]@{
                    TimeCreated = '2026-04-04 08:10:00'
                    Level = 'Error'
                    Source = 'Service Control Manager'
                    EventId = 7001
                    Message = 'Service start failed.'
                }
                [PSCustomObject]@{
                    TimeCreated = '2026-04-04 07:40:00'
                    Level = 'Warning'
                    Source = 'Service Control Manager'
                    EventId = 7009
                    Message = 'Service start timed out.'
                }
            )
        }

        $doc = Invoke-RecentChangesSummary -Scope 'C:\Users\chris\Desktop' -HoursBack 12 -Limit 5

        $doc.kind | Should -Be 'recent_changes_summary'
        $doc.summary.recent_file_count | Should -Be 2
        $doc.summary.recent_event_count | Should -Be 2
        $doc.summary.dominant_event_source | Should -Be 'Service Control Manager'
        $doc.recent_files[0].Path | Should -Be 'C:\Users\chris\Desktop\report.txt'
        $doc.recent_event_sources[0].Count | Should -Be 2
        @($doc.sources | ForEach-Object tool) | Should -Be @('Search-Files', 'Get-EventLogEntries')
    }

    It 'can emit JSON directly from the recent changes reducer' {
        Mock Search-Files { @() }
        Mock Get-EventLogEntries { @() }

        $json = Invoke-RecentChangesSummary -HoursBack 6 -AsJson
        $parsed = $json | ConvertFrom-Json

        $parsed.kind | Should -Be 'recent_changes_summary'
        $parsed.summary.recent_file_count | Should -Be 0
        $parsed.summary.recent_event_count | Should -Be 0
    }
}

Describe 'Loop behavior' {
    It 'feeds back unavailable-tool errors as proper tool_result turns and continues' {
        $script:CallCount = 0
        $script:CapturedMessages = @()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            if ($script:CallCount -eq 1) {
                return [PSCustomObject]@{
                    Type      = 'tool_call'
                    ToolName  = 'Get-NotApproved'
                    ToolInput = @{ Path = 'C:\temp' }
                    ToolUseId = 'toolu_missing'
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'handled unavailable tool'
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'do something' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-TopProcesses'
                    Description = 'Gets processes'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                }
            ) `
            -MaxSteps 2

        $result | Should -Be 'handled unavailable tool'
        $script:CallCount | Should -Be 2
        $script:CapturedMessages[1].Count | Should -Be 3
        $script:CapturedMessages[1][1].role | Should -Be 'assistant'
        $script:CapturedMessages[1][1].content[0].type | Should -Be 'tool_use'
        $script:CapturedMessages[1][1].content[0].name | Should -Be 'Get-NotApproved'
        $script:CapturedMessages[1][2].role | Should -Be 'user'
        $script:CapturedMessages[1][2].content[0].type | Should -Be 'tool_result'
        $script:CapturedMessages[1][2].content[0].tool_use_id | Should -Be 'toolu_missing'
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'not available'
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'Get-TopProcesses'
    }

    It 'adds workflow-specific multi-tool guidance for health-check prompts' {
        $script:CapturedSystemPrompt = $null

        Mock Send-ClawRequest {
            $script:CapturedSystemPrompt = $SystemPrompt
            [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'done'
            }
        }

        Mock Add-Content {}
        Mock Start-Sleep {}

        $null = Invoke-ClawLoop `
            -UserGoal 'Give me a full system health check' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-SystemTriage'
                    Description = 'Gets deterministic system triage'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                },
                [PSCustomObject]@{
                    Name = 'Get-SystemSummary'
                    Description = 'Gets system summary'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                },
                [PSCustomObject]@{
                    Name = 'Get-StorageStatus'
                    Description = 'Gets storage status'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                },
                [PSCustomObject]@{
                    Name = 'Get-NetworkStatus'
                    Description = 'Gets network status'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                }
            ) `
            -MaxSteps 1

        $script:CapturedSystemPrompt | Should -Match 'prefer the most synthesized read-only signal available'
        $script:CapturedSystemPrompt | Should -Match 'overall status first'
        $script:CapturedSystemPrompt | Should -Match 'start with Get-SystemTriage'
        $script:CapturedSystemPrompt | Should -Match 'already combines bounded system, process, service, event, and storage signals'
        $script:CapturedSystemPrompt | Should -Match 'Useful follow-up signals here: Get-StorageStatus, Get-NetworkStatus'
        $script:CapturedSystemPrompt | Should -Match 'usually finish in 1 to 3 tool calls'
        $script:CapturedSystemPrompt | Should -Match 'Prefer a fast first answer'
        $script:CapturedSystemPrompt | Should -Match 'prefer triage first, then storage or event issues if needed'
        $script:CapturedSystemPrompt | Should -Match 'Overall status, Key findings, Why it matters, Next checks'
        $script:CapturedSystemPrompt | Should -Match 'summary\.score is a risk score'
        $script:CapturedSystemPrompt | Should -Match 'Do not end a health check with a raw metric dump'
    }

    It 'treats whats going on with my system as a health-check prompt and explains triage score semantics' {
        $script:CapturedSystemPrompt = $null

        Mock Send-ClawRequest {
            $script:CapturedSystemPrompt = $SystemPrompt
            [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'done'
            }
        }

        Mock Add-Content {}
        Mock Start-Sleep {}

        $null = Invoke-ClawLoop `
            -UserGoal "what's going on with my system?" `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-SystemTriage'
                    Description = 'Gets deterministic system triage'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                }
            ) `
            -MaxSteps 1

        $script:CapturedSystemPrompt | Should -Match 'start with Get-SystemTriage'
        $script:CapturedSystemPrompt | Should -Match 'summary\.score is a risk score'
        $script:CapturedSystemPrompt | Should -Match 'A score of 0 means no warning or critical findings'
    }

    It 'adds a general final-answer interpretation rule to the system prompt' {
        $script:CapturedSystemPrompt = $null

        Mock Send-ClawRequest {
            $script:CapturedSystemPrompt = $SystemPrompt
            [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'done'
            }
        }

        Mock Add-Content {}
        Mock Start-Sleep {}

        $null = Invoke-ClawLoop `
            -UserGoal 'Give me a full system health check' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-SystemSummary'
                    Description = 'Gets system summary'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                }
            ) `
            -MaxSteps 1

        $script:CapturedSystemPrompt | Should -Match 'interpret the tool results for the user'
        $script:CapturedSystemPrompt | Should -Match 'Do not just restate tool names'
    }

    It 'adds workflow-specific recommendation guidance for cleanup prompts' {
        $script:CapturedSystemPrompt = $null

        Mock Send-ClawRequest {
            $script:CapturedSystemPrompt = $SystemPrompt
            [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'done'
            }
        }

        Mock Add-Content {}
        Mock Start-Sleep {}

        $null = Invoke-ClawLoop `
            -UserGoal 'Find the biggest files in Downloads and tell me what I should clean up' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-CleanupSummary'
                    Description = 'Gets deterministic cleanup summary'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                },
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                },
                [PSCustomObject]@{
                    Name = 'Get-DirectoryListing'
                    Description = 'Lists a directory'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                }
            ) `
            -MaxSteps 1

        $script:CapturedSystemPrompt | Should -Match 'Find the likely cleanup targets first'
        $script:CapturedSystemPrompt | Should -Match 'should not stop at raw listings'
        $script:CapturedSystemPrompt | Should -Match 'start with Get-CleanupSummary'
        $script:CapturedSystemPrompt | Should -Match 'Add context tools such as Get-DirectoryListing only when the first discovery result leaves real ambiguity'
        $script:CapturedSystemPrompt | Should -Match 'Do not keep issuing broad file-discovery searches with different scopes or sorts'
        $script:CapturedSystemPrompt | Should -Match 'usually finish in 1 to 2 tool calls'
        $script:CapturedSystemPrompt | Should -Match 'Do not recommend deletion just because a file is large'
        $script:CapturedSystemPrompt | Should -Match 'worth reviewing'
        $script:CapturedSystemPrompt | Should -Match 'separate likely-intentional files from disposable or stale candidates'
        $script:CapturedSystemPrompt | Should -Match 'review-only or execution-allowed'
    }

    It 'treats delete-identification phrasing as a cleanup goal' {
        Test-ClawCleanupGoal -UserGoal 'Please identify files that I can delete' | Should -BeTrue
        Test-ClawCleanupGoal -UserGoal 'What files can I delete from Downloads?' | Should -BeTrue
        Test-ClawCleanupGoal -UserGoal 'Show me files to delete' | Should -BeTrue
    }

    It 'treats disk and storage phrasing as a health-check goal' {
        Test-ClawHealthCheckGoal -UserGoal 'What about my hard drive?' | Should -BeTrue
        Test-ClawHealthCheckGoal -UserGoal 'How is my disk space?' | Should -BeTrue
        Test-ClawHealthCheckGoal -UserGoal 'Check my storage situation' | Should -BeTrue
    }

    It 'adds workflow-specific summary guidance for read and investigate prompts' {
        $script:CapturedSystemPrompt = $null

        Mock Send-ClawRequest {
            $script:CapturedSystemPrompt = $SystemPrompt
            [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'done'
            }
        }

        Mock Add-Content {}
        Mock Start-Sleep {}

        $null = Invoke-ClawLoop `
            -UserGoal 'Read config.json and explain my settings' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Read-FileContent'
                    Description = 'Reads files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                }
            ) `
            -MaxSteps 1

        $script:CapturedSystemPrompt | Should -Match 'start with a plain-English summary'
        $script:CapturedSystemPrompt | Should -Match 'specific settings, warnings, or takeaways'
        $script:CapturedSystemPrompt | Should -Match 'Implication or next step'
        $script:CapturedSystemPrompt | Should -Match 'usually finish in 1 to 2 tool calls'
        $script:CapturedSystemPrompt | Should -Match 'should not read like a transcript'
        $script:CapturedSystemPrompt | Should -Match 'answer directly instead of exploring sideways'
        $script:CapturedSystemPrompt | Should -Match 'answer, evidence, implication'
    }

    It 'treats webpage and config phrasing as an investigation goal' {
        Test-ClawInvestigationGoal -UserGoal 'Read config.json and explain my settings' | Should -BeTrue
        Test-ClawInvestigationGoal -UserGoal 'Summarize https://learn.microsoft.com/powershell/' | Should -BeTrue
        Test-ClawInvestigationGoal -UserGoal 'Inspect the README and tell me the main warnings' | Should -BeTrue
    }

    It 'blocks repeated identical tool calls and tells the model to use the earlier result' {
        $script:CallCount = 0
        $script:CapturedMessages = @()
        $script:Executions = 0

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            if ($script:CallCount -le 2) {
                return [PSCustomObject]@{
                    Type      = 'tool_call'
                    ToolName  = 'Get-TopProcesses'
                    ToolInput = @{ SortBy = 'CPU'; Count = 5 }
                    ToolUseId = "toolu_repeat_$script:CallCount"
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'handled repeat'
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'find the top processes' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-TopProcesses'
                    Description = 'Gets processes'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:Executions++
                        'ok'
                    }
                }
            ) `
            -MaxSteps 3

        $result | Should -Be 'handled repeat'
        $script:Executions | Should -Be 1
        $script:CapturedMessages[2][4].content[0].content | Should -Match 'ControlReason: repeated_identical_tool_call'
        $script:CapturedMessages[2][4].content[0].content | Should -Match 'repeated tool call detected'
        $script:CapturedMessages[2][4].content[0].content | Should -Match 'Do not call the same tool again'
    }

    It 'returns a dry-run tool_result without invoking the write tool' {
        $script:CallCount = 0
        $script:Executed = $false
        $script:CapturedMessages = @()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\temp'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_dryrun_search'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Remove-Files'
                        ToolInput = @{ Paths = @('C:\temp\old.log') }
                        ToolUseId = 'toolu_dryrun'
                    }
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'handled dry run'
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'delete that file' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Name Path SizeMB DateModified
old.log C:\temp\old.log 12.5 2026-04-04
'@
                    }
                }
                [PSCustomObject]@{
                    Name = 'Remove-Files'
                    Description = 'Deletes files'
                    Risk = 'Write'
                    Parameters = @()
                    ScriptBlock = {
                        $script:Executed = $true
                        'should not run'
                    }
                }
            ) `
            -MaxSteps 3 `
            -DryRun

        $result | Should -Be 'handled dry run'
        $script:Executed | Should -BeFalse
        $script:CapturedMessages[2][4].content[0].content | Should -Match 'PolicyReason: execution_mode_dry_run'
        $script:CapturedMessages[2][4].content[0].content | Should -Match 'dry run'
    }

    It 'uses simulated tool results in stub mode instead of executing the real tool' {
        $script:Executed = $false

        Mock Send-ClawRequest {
            if (-not $script:StubCallCount) {
                $script:StubCallCount = 1
                return [PSCustomObject]@{
                    Type      = 'tool_call'
                    ToolName  = 'Get-TopProcesses'
                    ToolInput = @{ SortBy = 'CPU'; Count = 5 }
                    ToolUseId = 'toolu_stub_demo'
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'stubbed final answer'
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'What is eating my CPU?' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-TopProcesses'
                    Description = 'Gets processes'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:Executed = $true
                        throw 'should not run'
                    }
                }
            ) `
            -Config ([PSCustomObject]@{
                max_output_chars = 500
                log_file = 'powerclaw.log'
            }) `
            -MaxSteps 2 `
            -UseStub

        $result | Should -Be 'stubbed final answer'
        $script:Executed | Should -BeFalse
    }

    It 'plan mode previews a short multi-step chain instead of stopping after step 1' {
        $script:CallCount = 0
        $script:CapturedMessages = @()
        $script:PlanLines = [System.Collections.Generic.List[string]]::new()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Get-SystemTriage'
                        ToolInput = @{}
                        ToolUseId = 'toolu_plan_1'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Get-StorageStatus'
                        ToolInput = @{ View = 'Summary' }
                        ToolUseId = 'toolu_plan_2'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'Summarize health status after checking system and storage.'
                    }
                }
            }
        }

        Mock Write-Host {
            $script:PlanLines.Add(($Object -join ' '))
        }
        Mock Add-Content {}
        Mock Start-Sleep {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Give me a full system health check' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-SystemTriage'
                    Description = 'Gets deterministic system triage'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                },
                [PSCustomObject]@{
                    Name = 'Get-SystemSummary'
                    Description = 'Gets system summary'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                },
                [PSCustomObject]@{
                    Name = 'Get-StorageStatus'
                    Description = 'Gets storage status'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                }
            ) `
            -MaxSteps 4 `
            -Plan

        $result | Should -BeNullOrEmpty
        $script:CallCount | Should -Be 3
        ($script:PlanLines -join "`n") | Should -Match 'Intended tool chain'
        ($script:PlanLines -join "`n") | Should -Match '1\. Get-SystemTriage'
        ($script:PlanLines -join "`n") | Should -Match '2\. Get-StorageStatus'
        ($script:PlanLines -join "`n") | Should -Match 'Summary: Overall status: Summarize health status'
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'ControlReason: plan_preview_only'
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'Plan preview only'
    }

    It 'plan mode stops after a short preview limit when the model keeps chaining tools' {
        $script:CallCount = 0
        $script:PlanLines = [System.Collections.Generic.List[string]]::new()

        Mock Send-ClawRequest {
            $script:CallCount++
            [PSCustomObject]@{
                Type      = 'tool_call'
                ToolName  = 'Get-TopProcesses'
                ToolInput = @{ SortBy = 'CPU'; Count = $script:CallCount }
                ToolUseId = "toolu_plan_limit_$script:CallCount"
            }
        }

        Mock Write-Host {
            $script:PlanLines.Add(($Object -join ' '))
        }
        Mock Add-Content {}
        Mock Start-Sleep {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Plan a diagnostic run' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-TopProcesses'
                    Description = 'Gets top processes'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                }
            ) `
            -MaxSteps 8 `
            -Plan

        $result | Should -BeNullOrEmpty
        $script:CallCount | Should -Be 3
        ($script:PlanLines -join "`n") | Should -Match '1\. Get-TopProcesses'
        ($script:PlanLines -join "`n") | Should -Match '2\. Get-TopProcesses'
        ($script:PlanLines -join "`n") | Should -Match '3\. Get-TopProcesses'
        ($script:PlanLines -join "`n") | Should -Match 'Run without -Plan to execute these steps for real'
    }

    It 'blocks write tools when the user goal does not explicitly request a destructive change' {
        $script:CallCount = 0
        $script:Executed = $false
        $script:CapturedMessages = @()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            if ($script:CallCount -eq 1) {
                return [PSCustomObject]@{
                    Type      = 'tool_call'
                    ToolName  = 'Remove-Files'
                    ToolInput = @{ Paths = @('C:\temp\old.log') }
                    ToolUseId = 'toolu_blocked'
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'handled blocked write'
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'inspect Downloads and tell me what looks safe to remove' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Remove-Files'
                    Description = 'Deletes files'
                    Risk = 'Write'
                    Parameters = @()
                    ScriptBlock = {
                        $script:Executed = $true
                        'should not run'
                    }
                }
            ) `
            -MaxSteps 2

        $result | Should -Be 'handled blocked write'
        $script:Executed | Should -BeFalse
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'Blocked by write policy'
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'did not explicitly ask for a destructive change'
    }

    It 'caps default health-check execution at three read-only tools and forces synthesis' {
        $script:CallCount = 0
        $script:CapturedMessages = @()
        $script:ExecutedTools = [System.Collections.Generic.List[string]]::new()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Get-SystemTriage'
                        ToolInput = @{}
                        ToolUseId = 'toolu_health_1'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Get-StorageStatus'
                        ToolInput = @{ View = 'Summary' }
                        ToolUseId = 'toolu_health_2'
                    }
                }
                3 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Get-EventLogEntries'
                        ToolInput = @{ LogName = 'System'; Level = 'Error'; Newest = 10 }
                        ToolUseId = 'toolu_health_3'
                    }
                }
                4 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Get-NetworkStatus'
                        ToolInput = @{}
                        ToolUseId = 'toolu_health_4'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'health summary from current signals'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Give me a full system health check' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-SystemTriage'
                    Description = 'Get-SystemTriage'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:ExecutedTools.Add('Get-SystemTriage') | Out-Null
                        'ok'
                    }
                }
                [PSCustomObject]@{
                    Name = 'Get-SystemSummary'
                    Description = 'Get-SystemSummary'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:ExecutedTools.Add('Get-SystemSummary') | Out-Null
                        'ok'
                    }
                }
                [PSCustomObject]@{
                    Name = 'Get-StorageStatus'
                    Description = 'Get-StorageStatus'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:ExecutedTools.Add('Get-StorageStatus') | Out-Null
                        'ok'
                    }
                }
                [PSCustomObject]@{
                    Name = 'Get-EventLogEntries'
                    Description = 'Get-EventLogEntries'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:ExecutedTools.Add('Get-EventLogEntries') | Out-Null
                        'ok'
                    }
                }
                [PSCustomObject]@{
                    Name = 'Get-NetworkStatus'
                    Description = 'Get-NetworkStatus'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:ExecutedTools.Add('Get-NetworkStatus') | Out-Null
                        'ok'
                    }
                }
            ) `
            -MaxSteps 5

        $result | Should -Be 'health summary from current signals'
        @($script:ExecutedTools) | Should -Be @('Get-SystemTriage', 'Get-StorageStatus', 'Get-EventLogEntries')
        $script:CapturedMessages[4][8].content[0].type | Should -Be 'tool_result'
        $script:CapturedMessages[4][8].content[0].content | Should -Match 'ControlReason: health_check_latency_budget_reached'
        $script:CapturedMessages[4][8].content[0].content | Should -Match 'Health-check latency budget reached'
        $script:CapturedMessages[4][8].content[0].content | Should -Match 'Answer now from the signals already gathered'
    }

    It 'caps default cleanup execution at two read-only tools and forces synthesis' {
        $script:CallCount = 0
        $script:CapturedMessages = @()
        $script:ExecutedTools = [System.Collections.Generic.List[string]]::new()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\Users\chris\Downloads'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_cleanup_1'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Get-DirectoryListing'
                        ToolInput = @{ Path = 'C:\Users\chris\Downloads'; Limit = 25 }
                        ToolUseId = 'toolu_cleanup_2'
                    }
                }
                3 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Read-FileContent'
                        ToolInput = @{ Path = 'C:\Users\chris\Downloads\driver-pack.exe' }
                        ToolUseId = 'toolu_cleanup_3'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'cleanup summary from current signals'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Find the biggest files in Downloads and tell me what I should clean up' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Search-Files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:ExecutedTools.Add('Search-Files') | Out-Null
                        'ok'
                    }
                }
                [PSCustomObject]@{
                    Name = 'Get-DirectoryListing'
                    Description = 'Get-DirectoryListing'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:ExecutedTools.Add('Get-DirectoryListing') | Out-Null
                        'ok'
                    }
                }
                [PSCustomObject]@{
                    Name = 'Read-FileContent'
                    Description = 'Read-FileContent'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:ExecutedTools.Add('Read-FileContent') | Out-Null
                        'ok'
                    }
                }
            ) `
            -MaxSteps 4

        $result | Should -Be 'cleanup summary from current signals'
        @($script:ExecutedTools) | Should -Be @('Search-Files', 'Get-DirectoryListing')
        $script:CapturedMessages[3][6].content[0].type | Should -Be 'tool_result'
        $script:CapturedMessages[3][6].content[0].content | Should -Match 'ControlReason: cleanup_latency_budget_reached'
        $script:CapturedMessages[3][6].content[0].content | Should -Match 'Cleanup latency budget reached'
        $script:CapturedMessages[3][6].content[0].content | Should -Match 'Answer now from the files and context already gathered'
    }

    It 'blocks repeated broad cleanup discovery searches even when the tool arguments change' {
        $script:CallCount = 0
        $script:CapturedMessages = @()
        $script:ExecutedTools = [System.Collections.Generic.List[string]]::new()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\Users\chris\Downloads'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_cleanup_search_1'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Get-StorageStatus'
                        ToolInput = @{ View = 'Summary' }
                        ToolUseId = 'toolu_cleanup_storage_2'
                    }
                }
                3 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\Users\chris\Desktop'; Limit = 25; SortBy = 'DateModified'; Aggregate = $false }
                        ToolUseId = 'toolu_cleanup_search_3'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'cleanup summary from surfaced files'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Please identify files that I can delete' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Search-Files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:ExecutedTools.Add('Search-Files') | Out-Null
                        'ok'
                    }
                }
                [PSCustomObject]@{
                    Name = 'Get-StorageStatus'
                    Description = 'Get-StorageStatus'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:ExecutedTools.Add('Get-StorageStatus') | Out-Null
                        'ok'
                    }
                }
            ) `
            -MaxSteps 4

        $result | Should -Be 'cleanup summary from surfaced files'
        @($script:ExecutedTools) | Should -Be @('Search-Files', 'Get-StorageStatus')
        $script:CapturedMessages[3][6].content[0].type | Should -Be 'tool_result'
        $script:CapturedMessages[3][6].content[0].content | Should -Match 'ControlReason: cleanup_discovery_budget_reached'
        $script:CapturedMessages[3][6].content[0].content | Should -Match 'Cleanup discovery budget reached'
        $script:CapturedMessages[3][6].content[0].content | Should -Match 'Do not keep searching with new scopes or sorts'
    }

    It 'caps default investigation execution at two read-only tools and forces synthesis' {
        $script:CallCount = 0
        $script:CapturedMessages = @()
        $script:ExecutedTools = [System.Collections.Generic.List[string]]::new()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Read-FileContent'
                        ToolInput = @{ Path = 'C:\dev\repos\PowerClaw\config.example.json' }
                        ToolUseId = 'toolu_investigation_1'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Read-FileContent'
                        ToolInput = @{ Path = 'C:\dev\repos\PowerClaw\README.md' }
                        ToolUseId = 'toolu_investigation_2'
                    }
                }
                3 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Read-FileContent'
                        ToolInput = @{ Path = 'C:\dev\repos\PowerClaw\docs\roadmap.md' }
                        ToolUseId = 'toolu_investigation_3'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'investigation summary from current evidence'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Read config.example.json and explain the important settings' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Read-FileContent'
                    Description = 'Reads files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        $script:ExecutedTools.Add('Read-FileContent') | Out-Null
                        'ok'
                    }
                }
            ) `
            -MaxSteps 4

        $result | Should -Be 'investigation summary from current evidence'
        @($script:ExecutedTools) | Should -Be @('Read-FileContent', 'Read-FileContent')
        $script:CapturedMessages[3][6].content[0].type | Should -Be 'tool_result'
        $script:CapturedMessages[3][6].content[0].content | Should -Match 'ControlReason: investigation_latency_budget_reached'
        $script:CapturedMessages[3][6].content[0].content | Should -Match 'Investigation latency budget reached'
        $script:CapturedMessages[3][6].content[0].content | Should -Match 'Answer now from the source material already gathered'
    }

    It 'normalizes thin cleanup final answers into review-oriented sections' {
        $script:CallCount = 0

        Mock Send-ClawRequest {
            $script:CallCount++

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\Users\chris\Downloads'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_cleanup_shape_1'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'driver-pack.exe is probably the main cleanup target from the current results.'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Find the biggest files in Downloads and tell me what I should clean up' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Name Path SizeMB DateModified
driver-pack.exe C:\Users\chris\Downloads\driver-pack.exe 812.1 2026-02-11
'@
                    }
                }
            ) `
            -MaxSteps 2

        $result | Should -Match '^What I found: driver-pack\.exe is probably the main cleanup target'
        $result | Should -Match 'What looks worth reviewing:'
        $result | Should -Match 'driver-pack\.exe'
        $result | Should -Match 'What is ambiguous or risky:'
        $result | Should -Match 'Next safe action:'
    }

    It 'tailors cleanup ambiguity guidance to surfaced file categories' {
        $script:CallCount = 0

        Mock Send-ClawRequest {
            $script:CallCount++

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\Users\chris\Downloads'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_cleanup_shape_2'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'These look like the main cleanup candidates from Downloads.'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Find the biggest files in Downloads and tell me what I should clean up' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Name Path SizeMB DateModified
driver-pack.exe C:\Users\chris\Downloads\driver-pack.exe 812.1 2026-02-11
windows-iso-backup.zip C:\Users\chris\Downloads\windows-iso-backup.zip 5820.4 2026-03-28
obs-recording.mp4 C:\Users\chris\Downloads\obs-recording.mp4 2144.8 2026-04-02
debug.log C:\Users\chris\Downloads\debug.log 40.2 2026-04-03
'@
                    }
                }
            ) `
            -MaxSteps 2

        $result | Should -Match 'setup packages can be disposable'
        $result | Should -Match 'Archives may be backups'
        $result | Should -Match 'media files are often intentional recordings'
        $result | Should -Match 'Logs, temp files, dumps, or backup-style remnants are usually stronger cleanup candidates'
    }

    It 'ranks cleanup review recommendations by likely disposability' {
        $script:CallCount = 0

        Mock Send-ClawRequest {
            $script:CallCount++

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\Users\chris\Downloads'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_cleanup_shape_3'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'These are the main files worth reviewing.'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Find the biggest files in Downloads and tell me what I should clean up' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Name Path SizeMB DateModified
debug.log C:\Users\chris\Downloads\debug.log 40.2 2026-04-03
driver-pack.exe C:\Users\chris\Downloads\driver-pack.exe 812.1 2026-02-11
windows-iso-backup.zip C:\Users\chris\Downloads\windows-iso-backup.zip 5820.4 2026-03-28
obs-recording.mp4 C:\Users\chris\Downloads\obs-recording.mp4 2144.8 2026-04-02
'@
                    }
                }
            ) `
            -MaxSteps 2

        $result | Should -Match 'Review order: logs, temp files, and dump-style remnants, then one-time installers or setup images, then archives and bundled backups, then large media files\.'
    }

    It 'adds explicit cleanup candidate states for review-only versus execution-allowed items' {
        $script:CallCount = 0

        Mock Send-ClawRequest {
            $script:CallCount++

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\Users\chris\Downloads'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_cleanup_shape_4'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'These are the current cleanup candidates.'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Find the biggest files in Downloads and tell me what I should clean up' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Name Path SizeMB DateModified
debug.log C:\Users\chris\Downloads\debug.log 40.2 2026-04-03
driver-pack.exe C:\Users\chris\Downloads\driver-pack.exe 812.1 2026-02-11
windows-iso-backup.zip C:\Users\chris\Downloads\windows-iso-backup.zip 5820.4 2026-03-28
obs-recording.mp4 C:\Users\chris\Downloads\obs-recording.mp4 2144.8 2026-04-02
'@
                    }
                }
            ) `
            -MaxSteps 2

        $result | Should -Match 'Candidate states:'
        $result | Should -Match 'execution-allowed after confirmation: logs, temp files, dumps, and backup-style remnants that were already enumerated'
        $result | Should -Match 'review-only: installers and setup images unless the user names them specifically'
        $result | Should -Match 'review-only: archives and backup bundles unless the user confirms they are redundant'
        $result | Should -Match 'review-only: media files unless the user clearly identifies the exact recording or download'
    }

    It 'normalizes thin investigation final answers into answer-evidence-implication sections' {
        $script:CallCount = 0

        Mock Send-ClawRequest {
            $script:CallCount++

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Read-FileContent'
                        ToolInput = @{ Path = 'C:\dev\repos\PowerClaw\config.example.json' }
                        ToolUseId = 'toolu_investigation_shape_1'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'The config is set up for OpenAI and points at gpt-4.1-mini.'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Read config.example.json and explain the important settings' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Read-FileContent'
                    Description = 'Reads files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Path       : C:\dev\repos\PowerClaw\config.example.json
LinesShown : 4
Truncated  : False
Content    : provider=openai
             model=gpt-4.1-mini
'@
                    }
                }
            ) `
            -MaxSteps 2

        $result | Should -Match '^Answer: The config is set up for OpenAI and points at gpt-4\.1-mini\.'
        $result | Should -Match '(?m)^Evidence: '
        $result | Should -Match 'provider=openai'
        $result | Should -Match '(?m)^Implication: '
    }

    It 'normalizes thin health final answers into operator-summary sections' {
        $script:CallCount = 0

        Mock Send-ClawRequest {
            $script:CallCount++

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Get-SystemSummary'
                        ToolInput = @{ View = 'Full' }
                        ToolUseId = 'toolu_health_shape_1'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'The machine looks broadly healthy, with memory usage worth keeping an eye on.'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'Give me a full system health check' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-SystemSummary'
                    Description = 'Gets system summary'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
MachineName : DEMO-PC
OSVersion   : Windows 11 Pro
Uptime      : 4d 6h 12m
CPULoadPct  : 18
RAMUsedPct  : 63
TopByCPU    : pwsh (14.2 CPU), chrome (9.8 CPU), Code (4.1 CPU)
TopByMemory : chrome (1240 MB), Code (812 MB), pwsh (220 MB)
'@
                    }
                }
            ) `
            -MaxSteps 2

        $result | Should -Match '^Overall status: The machine looks broadly healthy, with memory usage worth keeping an eye on\.'
        $result | Should -Match '(?m)^Key findings: '
        $result | Should -Match 'CPULoadPct'
        $result | Should -Match '(?m)^Why it matters: '
        $result | Should -Match '(?m)^Next checks: '
    }

    It 'normalizes thin recent-change final answers into bounded summary sections' {
        $script:CallCount = 0

        Mock Send-ClawRequest {
            $script:CallCount++

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Get-RecentChangesSummary'
                        ToolInput = @{ Scope = 'C:\Users\chris'; HoursBack = 24; Limit = 10 }
                        ToolUseId = 'toolu_recent_shape_1'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'Most recent activity appears to be a few user file edits plus repeated Service Control Manager events.'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'What changed on this machine in the last 24 hours?' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-RecentChangesSummary'
                    Description = 'Gets recent changes summary'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
kind                 : recent_changes_summary
captured_at          : 2026-04-04T18:05:00-05:00
scope                : C:\Users\chris
window_hours         : 24
summary              : @{headline=Recent changes in the last 24 hours include 2 surfaced files and 3 recent events, led by Service Control Manager.; recent_file_count=2; recent_event_count=3; dominant_event_source=Service Control Manager}
recent_files         : {@{Name=report.txt; Path=C:\Users\chris\Desktop\report.txt; SizeMB=1.2; DateModified=2026-04-04T08:15:00-05:00}}
recent_event_sources : {@{Source=Service Control Manager; Count=3; LatestEventTime=2026-04-04 08:10:00}}
'@
                    }
                }
            ) `
            -MaxSteps 2

        $result | Should -Match '^What changed: Most recent activity appears to be a few user file edits plus repeated Service Control Manager events\.'
        $result | Should -Match '(?m)^What stands out: '
        $result | Should -Match 'recent_event_sources'
        $result | Should -Match '(?m)^Implication: '
        $result | Should -Match '(?m)^Next checks: '
    }

    It 'reports user decline as a proper tool_result turn and does not invoke the write tool' {
        $script:CallCount = 0
        $script:Executed = $false
        $script:CapturedMessages = @()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\temp'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_decline_search'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Remove-Files'
                        ToolInput = @{ Paths = @('C:\temp\old.log') }
                        ToolUseId = 'toolu_decline'
                    }
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'handled decline'
            }
        }

        Mock Read-Host { 'nope' }
        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'delete that file' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Name Path SizeMB DateModified
old.log C:\temp\old.log 12.5 2026-04-04
'@
                    }
                }
                [PSCustomObject]@{
                    Name = 'Remove-Files'
                    Description = 'Deletes files'
                    Risk = 'Write'
                    Parameters = @()
                    ScriptBlock = {
                        $script:Executed = $true
                        'should not run'
                    }
                }
            ) `
            -MaxSteps 3

        $result | Should -Be 'handled decline'
        $script:Executed | Should -BeFalse
        $script:CallCount | Should -Be 3
        $script:CapturedMessages[2][3].content[0].type | Should -Be 'tool_use'
        $script:CapturedMessages[2][4].content[0].type | Should -Be 'tool_result'
        $script:CapturedMessages[2][4].content[0].tool_use_id | Should -Be 'toolu_decline'
        $script:CapturedMessages[2][4].content[0].content | Should -Match 'PolicyReason: confirmation_declined'
        $script:CapturedMessages[2][4].content[0].content | Should -Match 'declined'
        $script:CapturedMessages[2][4].content[0].content | Should -Match 'REMOVE-FILES'
    }

    It 'requires the exact write confirmation token before executing a destructive tool' {
        $script:CallCount = 0
        $script:Executed = $false

        Mock Send-ClawRequest {
            $script:CallCount++

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\temp'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_confirm_search'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Remove-Files'
                        ToolInput = @{ Paths = @('C:\temp\old.log') }
                        ToolUseId = 'toolu_confirmed'
                    }
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'handled confirmed delete'
            }
        }

        Mock Read-Host { 'REMOVE-FILES' }
        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'delete that file' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Name Path SizeMB DateModified
old.log C:\temp\old.log 12.5 2026-04-04
'@
                    }
                }
                [PSCustomObject]@{
                    Name = 'Remove-Files'
                    Description = 'Deletes files'
                    Risk = 'Write'
                    Parameters = @()
                    ScriptBlock = {
                        $script:Executed = $true
                        'deleted'
                    }
                }
            ) `
            -MaxSteps 3

        $result | Should -Be 'handled confirmed delete'
        $script:Executed | Should -BeTrue
    }

    It 'blocks Remove-Files when the exact target paths were not previously shown by read-only tools' {
        $script:CallCount = 0
        $script:Executed = $false
        $script:CapturedMessages = @()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            if ($script:CallCount -eq 1) {
                return [PSCustomObject]@{
                    Type      = 'tool_call'
                    ToolName  = 'Remove-Files'
                    ToolInput = @{ Paths = @('C:\temp\old.log') }
                    ToolUseId = 'toolu_needs_evidence'
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'handled missing evidence'
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'delete that file' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Remove-Files'
                    Description = 'Deletes files'
                    Risk = 'Write'
                    Parameters = @()
                    ScriptBlock = {
                        $script:Executed = $true
                        'should not run'
                    }
                }
            ) `
            -MaxSteps 2

        $result | Should -Be 'handled missing evidence'
        $script:Executed | Should -BeFalse
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'PolicyReason: prior_evidence_required'
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'exact paths that were already shown'
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'enumerate the candidate files with a read-only tool'
    }

    It 'allows Remove-Files after the exact full path was shown earlier in the same request' {
        $script:CallCount = 0
        $script:Executed = $false
        $script:CapturedMessages = @()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\temp'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_search_first'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Remove-Files'
                        ToolInput = @{ Paths = @('C:\temp\old.log') }
                        ToolUseId = 'toolu_delete_after_search'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'handled evidence-backed delete'
                    }
                }
            }
        }

        Mock Read-Host { 'REMOVE-FILES' }
        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'delete that file' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Name Path SizeMB DateModified
old.log C:\temp\old.log 12.5 2026-04-04
'@
                    }
                }
                [PSCustomObject]@{
                    Name = 'Remove-Files'
                    Description = 'Deletes files'
                    Risk = 'Write'
                    Parameters = @()
                    ScriptBlock = {
                        $script:Executed = $true
                        'deleted'
                    }
                }
            ) `
            -MaxSteps 3

        $result | Should -Be 'handled evidence-backed delete'
        $script:Executed | Should -BeTrue
    }

    It 'blocks permanent delete unless the user explicitly asks for permanent removal' {
        $script:CallCount = 0
        $script:Executed = $false
        $script:CapturedMessages = @()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\temp'; Limit = 5; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_perm_search'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Remove-Files'
                        ToolInput = @{ Paths = @('C:\temp\cleanup.log'); Permanent = $true }
                        ToolUseId = 'toolu_perm_delete'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'handled permanent block'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'delete that file' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Name Path SizeMB DateModified
cleanup.log C:\temp\cleanup.log 12.5 2026-04-04
'@
                    }
                }
                [PSCustomObject]@{
                    Name = 'Remove-Files'
                    Description = 'Deletes files'
                    Risk = 'Write'
                    Parameters = @()
                    ScriptBlock = {
                        $script:Executed = $true
                        'should not run'
                    }
                }
            ) `
            -MaxSteps 3

        $result | Should -Be 'handled permanent block'
        $script:Executed | Should -BeFalse
        $script:CapturedMessages[2][4].content[0].content | Should -Match 'permanent deletion requires explicit permanent intent'
    }

    It 'blocks sensitive delete targets unless the user references them specifically' {
        $script:CallCount = 0
        $script:Executed = $false
        $script:CapturedMessages = @()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\Users\chris\Downloads'; Limit = 5; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_sensitive_search'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Remove-Files'
                        ToolInput = @{ Paths = @('C:\Users\chris\Downloads\obs-recording.mp4') }
                        ToolUseId = 'toolu_sensitive_delete'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'handled sensitive block'
                    }
                }
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'delete that file' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Name Path SizeMB DateModified
obs-recording.mp4 C:\Users\chris\Downloads\obs-recording.mp4 2144.8 2026-04-02
'@
                    }
                }
                [PSCustomObject]@{
                    Name = 'Remove-Files'
                    Description = 'Deletes files'
                    Risk = 'Write'
                    Parameters = @()
                    ScriptBlock = {
                        $script:Executed = $true
                        'should not run'
                    }
                }
            ) `
            -MaxSteps 3

        $result | Should -Be 'handled sensitive block'
        $script:Executed | Should -BeFalse
        $script:CapturedMessages[2][4].content[0].content | Should -Match 'need a more specific user instruction'
        $script:CapturedMessages[2][4].content[0].content | Should -Match 'exact file, path, or file type'
    }

    It 'still allows lower-risk delete targets after prior enumeration and confirmation' {
        $script:CallCount = 0
        $script:Executed = $false

        Mock Send-ClawRequest {
            $script:CallCount++

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\temp'; Limit = 5; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_lowrisk_search'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Remove-Files'
                        ToolInput = @{ Paths = @('C:\temp\cleanup.log') }
                        ToolUseId = 'toolu_lowrisk_delete'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'handled low-risk delete'
                    }
                }
            }
        }

        Mock Read-Host { 'REMOVE-FILES' }
        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'delete that file' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Search-Files'
                    Description = 'Searches files'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = {
                        @'
Name Path SizeMB DateModified
cleanup.log C:\temp\cleanup.log 12.5 2026-04-04
'@
                    }
                }
                [PSCustomObject]@{
                    Name = 'Remove-Files'
                    Description = 'Deletes files'
                    Risk = 'Write'
                    Parameters = @()
                    ScriptBlock = {
                        $script:Executed = $true
                        'deleted'
                    }
                }
            ) `
            -MaxSteps 3

        $result | Should -Be 'handled low-risk delete'
        $script:Executed | Should -BeTrue
    }

    It 'feeds tool execution failures back as tool_result errors and continues' {
        $script:CallCount = 0
        $script:CapturedMessages = @()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            if ($script:CallCount -eq 1) {
                return [PSCustomObject]@{
                    Type      = 'tool_call'
                    ToolName  = 'Get-TopProcesses'
                    ToolInput = @{ SortBy = 'CPU' }
                    ToolUseId = 'toolu_fail'
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'handled failure'
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}

        $result = Invoke-ClawLoop `
            -UserGoal 'do something' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-TopProcesses'
                    Description = 'Gets processes'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { throw 'boom' }
                }
            ) `
            -MaxSteps 2

        $result | Should -Be 'handled failure'
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'Get-TopProcesses failed'
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'Do not retry'
    }

    It 'truncates oversized tool output once and sends the truncation instruction back' {
        $script:CallCount = 0
        $script:CapturedMessages = @()
        $script:Warnings = @()

        Mock Send-ClawRequest {
            $script:CallCount++
            $script:CapturedMessages += ,$Messages

            if ($script:CallCount -eq 1) {
                return [PSCustomObject]@{
                    Type      = 'tool_call'
                    ToolName  = 'Get-TopProcesses'
                    ToolInput = @{ SortBy = 'CPU' }
                    ToolUseId = 'toolu_big'
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'handled truncation'
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {}
        Mock Write-Warning {
            $script:Warnings += $Message
        }

        $result = Invoke-ClawLoop `
            -UserGoal 'do something' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-TopProcesses'
                    Description = 'Gets processes'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ' }
                }
            ) `
            -Config ([PSCustomObject]@{
                max_output_chars = 40
                log_file = 'powerclaw.log'
            }) `
            -MaxSteps 2

        $result | Should -Be 'handled truncation'
        $script:Warnings.Count | Should -Be 1
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'truncated'
        $script:CapturedMessages[1][2].content[0].content | Should -Match 'Do not call this tool again'
    }

    It 'writes structured log entries for step start, tool execution, and final answer' {
        $script:CallCount = 0
        $script:LogEntries = @()
        $schemaPath = Join-Path $script:RepoRoot 'docs\loop-log-v1.schema.json'

        Mock Send-ClawRequest {
            $script:CallCount++

            if ($script:CallCount -eq 1) {
                return [PSCustomObject]@{
                    Type      = 'tool_call'
                    ToolName  = 'Get-TopProcesses'
                    ToolInput = @{ SortBy = 'CPU' }
                    ToolUseId = 'toolu_log'
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'done'
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {
            $script:LogEntries += ($Value | ConvertFrom-Json -Depth 10)
        }

        $result = Invoke-ClawLoop `
            -UserGoal 'check processes' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-TopProcesses'
                    Description = 'Gets processes'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                }
            ) `
            -Config ([PSCustomObject]@{
                max_output_chars = 500
                log_file = 'powerclaw.log'
            }) `
            -MaxSteps 2

        $result | Should -Be 'done'
        @($script:LogEntries | Where-Object { $_.Event -eq 'step_start' }).Count | Should -BeGreaterThan 0
        @($script:LogEntries | Where-Object { $_.Event -eq 'tool_requested' }).Count | Should -Be 1
        @($script:LogEntries | Where-Object { $_.Event -eq 'tool_result' -and $_.Status -eq 'success' -and $_.Outcome -eq 'success' }).Count | Should -Be 1
        @($script:LogEntries | Where-Object { $_.Event -eq 'final_answer' -and $_.Outcome -eq 'final_answer' }).Count | Should -Be 1
        $toolResultEntry = $script:LogEntries | Where-Object { $_.Event -eq 'tool_result' } | Select-Object -First 1
        $toolResultEntry.ToolUseId | Should -Be 'toolu_log'
        $toolResultEntry.SchemaVersion | Should -Be '1'
        $toolResultEntry.Kind | Should -Be 'loop_log'
        $toolResultEntry.Timestamp | Should -Not -BeNullOrEmpty
        $toolResultEntry.Step | Should -Be 1
        $toolResultEntry.Tool | Should -Be 'Get-TopProcesses'
        foreach ($entry in $script:LogEntries) {
            (($entry | ConvertTo-Json -Depth 10 -Compress) | Test-Json -SchemaFile $schemaPath) | Should -BeTrue
        }
    }

    It 'logs blocked, declined, and executed write outcomes distinctly' {
        $script:LogEntries = @()
        $script:CallCount = 0
        $script:ReadHostResponse = 'nope'

        Mock Send-ClawRequest {
            $script:CallCount++

            if ($script:CallCount -eq 1) {
                return [PSCustomObject]@{
                    Type      = 'tool_call'
                    ToolName  = 'Remove-Files'
                    ToolInput = @{ Paths = @('C:\temp\old.log') }
                    ToolUseId = 'toolu_write_gate'
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'done'
            }
        }

        Mock Read-Host { $script:ReadHostResponse }
        Mock Start-Sleep {}
        Mock Add-Content {
            $script:LogEntries += ($Value | ConvertFrom-Json -Depth 10)
        }

        $removeTool = [PSCustomObject]@{
            Name = 'Remove-Files'
            Description = 'Deletes files'
            Risk = 'Write'
            Parameters = @()
            ScriptBlock = { 'deleted' }
        }
        $searchTool = [PSCustomObject]@{
            Name = 'Search-Files'
            Description = 'Searches files'
            Risk = 'ReadOnly'
            Parameters = @()
            ScriptBlock = {
                @'
Name Path SizeMB DateModified
old.log C:\temp\old.log 12.5 2026-04-04
'@
            }
        }

        $null = Invoke-ClawLoop -UserGoal 'inspect Downloads and tell me what looks safe to remove' -Tools @($removeTool) -Config ([PSCustomObject]@{ max_output_chars = 500; log_file = 'powerclaw.log' }) -MaxSteps 2
        @($script:LogEntries | Where-Object { $_.Event -eq 'tool_skipped' -and $_.Outcome -eq 'blocked' -and $_.Reason -eq 'write_policy_blocked' -and $_.PolicyReason -eq 'explicit_write_intent_required' }).Count | Should -Be 1

        $script:LogEntries = @()
        $script:CallCount = 0
        $script:ReadHostResponse = 'nope'
        Mock Send-ClawRequest {
            $script:CallCount++

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\temp'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_write_gate_search_decline'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Remove-Files'
                        ToolInput = @{ Paths = @('C:\temp\old.log') }
                        ToolUseId = 'toolu_write_gate_decline'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'done'
                    }
                }
            }
        }
        $null = Invoke-ClawLoop -UserGoal 'delete that file' -Tools @($searchTool, $removeTool) -Config ([PSCustomObject]@{ max_output_chars = 500; log_file = 'powerclaw.log' }) -MaxSteps 3
        @($script:LogEntries | Where-Object { $_.Event -eq 'tool_skipped' -and $_.Outcome -eq 'declined' -and $_.Reason -eq 'confirmation_declined' -and $_.PolicyReason -eq 'confirmation_declined' }).Count | Should -Be 1

        $script:LogEntries = @()
        $script:CallCount = 0
        $script:ReadHostResponse = 'REMOVE-FILES'
        Mock Send-ClawRequest {
            $script:CallCount++

            switch ($script:CallCount) {
                1 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Search-Files'
                        ToolInput = @{ Scope = 'C:\temp'; Limit = 10; SortBy = 'Size'; Aggregate = $false }
                        ToolUseId = 'toolu_write_gate_search_confirm'
                    }
                }
                2 {
                    return [PSCustomObject]@{
                        Type      = 'tool_call'
                        ToolName  = 'Remove-Files'
                        ToolInput = @{ Paths = @('C:\temp\old.log') }
                        ToolUseId = 'toolu_write_gate_confirm'
                    }
                }
                default {
                    return [PSCustomObject]@{
                        Type    = 'final_answer'
                        Content = 'done'
                    }
                }
            }
        }
        $null = Invoke-ClawLoop -UserGoal 'delete that file' -Tools @($searchTool, $removeTool) -Config ([PSCustomObject]@{ max_output_chars = 500; log_file = 'powerclaw.log' }) -MaxSteps 3
        @($script:LogEntries | Where-Object { $_.Event -eq 'tool_confirmed' -and $_.Outcome -eq 'confirmed' }).Count | Should -Be 1
        @($script:LogEntries | Where-Object { $_.Event -eq 'tool_result' -and $_.Outcome -eq 'executed_success' -and $_.PolicyReason -eq 'confirmed_write_execution' }).Count | Should -Be 1
    }

    It 'emits the supported core log fields on every structured entry' {
        $script:CallCount = 0
        $script:LogEntries = @()
        $schemaPath = Join-Path $script:RepoRoot 'docs\loop-log-v1.schema.json'

        Mock Send-ClawRequest {
            $script:CallCount++

            if ($script:CallCount -eq 1) {
                return [PSCustomObject]@{
                    Type      = 'tool_call'
                    ToolName  = 'Get-TopProcesses'
                    ToolInput = @{ SortBy = 'CPU' }
                    ToolUseId = 'toolu_core_fields'
                }
            }

            return [PSCustomObject]@{
                Type    = 'final_answer'
                Content = 'done'
            }
        }

        Mock Start-Sleep {}
        Mock Add-Content {
            $script:LogEntries += ($Value | ConvertFrom-Json -Depth 10)
        }

        $null = Invoke-ClawLoop `
            -UserGoal 'check processes' `
            -Tools @(
                [PSCustomObject]@{
                    Name = 'Get-TopProcesses'
                    Description = 'Gets processes'
                    Risk = 'ReadOnly'
                    Parameters = @()
                    ScriptBlock = { 'ok' }
                }
            ) `
            -Config ([PSCustomObject]@{
                max_output_chars = 500
                log_file = 'powerclaw.log'
            }) `
            -MaxSteps 2

        foreach ($entry in $script:LogEntries) {
            $entry.SchemaVersion | Should -Be '1'
            $entry.Kind | Should -Be 'loop_log'
            $entry.Timestamp | Should -Not -BeNullOrEmpty
            $entry.Event | Should -Not -BeNullOrEmpty
            $entry.Outcome | Should -Not -BeNullOrEmpty
            $entry.Step | Should -BeGreaterThan 0
            (($entry | ConvertTo-Json -Depth 10 -Compress) | Test-Json -SchemaFile $schemaPath) | Should -BeTrue
        }
    }
}
