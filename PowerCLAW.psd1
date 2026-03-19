@{
    ModuleVersion     = '0.1.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Chris'
    Description       = 'PowerShell Command-Line Agentic Workbench — LLM-guided tool orchestration'
    PowerShellVersion = '7.0'
    RootModule        = 'PowerClaw.psm1'
    FunctionsToExport = @('Invoke-PowerClaw')
    PrivateData       = @{
        PSData = @{
            Tags = @('AI', 'Automation', 'LLM', 'Claude', 'Agentic')
        }
    }
}
