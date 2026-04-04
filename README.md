# PowerClaw

**PowerShell Command-Line Agentic Workbench** &nbsp;·&nbsp; [🌐 spinchange.github.io/PowerClaw](https://spinchange.github.io/PowerClaw/)

A Windows-native agentic automation framework built on PowerShell 7. You describe what you want in plain English — PowerClaw uses a configured LLM provider to pick the right tool, runs it on your machine, and returns a human-readable answer.

The model never generates raw PowerShell. It picks from a registry of approved, auditable tools you control.

---

## Requirements

- PowerShell 7+
- Anthropic or OpenAI API key
- Windows 10/11

## Setup

**1. Clone the repo**
```powershell
git clone https://github.com/spinchange/PowerClaw.git
cd PowerClaw
```

**2. Set your API key**
```powershell
$env:CLAUDE_API_KEY = 'sk-ant-...'
```

To persist across sessions, add it to your PowerShell profile.

If you want to use OpenAI instead, set `config.json` to `"provider": "openai"`,
choose an OpenAI-compatible model, and point `api_key_env` at your OpenAI key env var.

### Provider quickstart

| Provider | `provider` | API key env var | Example model |
|----------|------------|-----------------|---------------|
| Anthropic | `claude` | `CLAUDE_API_KEY` | `claude-sonnet-4-20250514` |
| OpenAI | `openai` | `OPENAI_API_KEY` | `gpt-4.1-mini` |

**3. Import the module**
```powershell
Import-Module .\PowerClaw.psd1
```

This exports both `Invoke-PowerClaw` and the ergonomic alias `powerclaw`.

**4. Run a prompt**
```powershell
powerclaw "What are the top 5 processes by memory?"
```

**5. Validate setup**
```powershell
Test-PowerClawSetup
```

## Optional: Persistent local install

If you keep source repos under `C:\dev\repos`, install the module into a separate
PowerShell module root and install the `powerclaw.ps1` launcher into a bin directory:

```powershell
pwsh -File .\Install-PowerClaw.ps1 -ModuleRoot C:\dev\powershell-modules -BinRoot C:\dev\bin
```

Then make sure:

- `C:\dev\powershell-modules` is on `PSModulePath`
- `C:\dev\bin` is on `PATH`

After that, `powerclaw` works as a real shell command in a new PowerShell session:

```powershell
powerclaw "What's eating my CPU?"
```

If you want a starting config to edit, copy `config.example.json` to `config.json`
and then set the provider, model, and API key env var for your setup.

---

## Optional: Fetch-WebPage (Playwright setup)

The `Fetch-WebPage` tool requires a one-time Playwright browser install:

```powershell
$dir = "$env:USERPROFILE\.powerclaw-playwright\PwHost"
mkdir $dir -Force; cd $dir
dotnet new console -n PwHost --framework net10.0 --force
cd PwHost
dotnet add package Microsoft.Playwright
dotnet build
pwsh bin/Debug/net10.0/playwright.ps1 install chromium
```

---

## Usage

```powershell
# Basic prompt
powerclaw "Give me a full system health check"

# See what Claude would do without running it
powerclaw -Plan "Find the 10 biggest files in Downloads"

# Test without an API key
powerclaw -UseStub "anything"

# Verbose
powerclaw -Verbose "What's eating my CPU?"

# Validate setup
Test-PowerClawSetup
```

For scripts or explicit PowerShell style, `Invoke-PowerClaw` remains available.

## Tests

PowerClaw now uses a Pester 5 suite.

Run the repo test suite with:

```powershell
pwsh -File .\Run-Tests.ps1
```

If Pester 5.7.1 is not installed yet:

```powershell
Install-Module -Name Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
```

---

## Tools

| Tool | Category | What it does |
|------|----------|-------------|
| `Get-SystemSummary` | SystemInfo | CPU, RAM, uptime, top processes |
| `Get-TopProcesses` | SystemInfo | Processes sorted by CPU or memory |
| `Get-EventLogEntries` | SystemInfo | Windows event log errors and warnings |
| `Get-ServiceStatus` | SystemInfo | Windows service health |
| `Get-NetworkStatus` | Network | Interfaces, connections, external IP |
| `Get-StorageStatus` | Filesystem | Disk usage and largest folders |
| `Get-DirectoryListing` | Filesystem | List files in a directory |
| `Search-Files` | Filesystem | Windows Search index queries |
| `Read-FileContent` | Filesystem | Read and reason about any file |
| `Remove-Files` | Filesystem | Delete files (Recycle Bin by default) |
| `Fetch-WebPage` | Web | Fetch any URL, returns clean text |
| `Search-MyJoNotes` | Personal | Search MyJo journal notebooks |
| `Search-MnVault` | Personal | Search mnvault markdown notes |

The `Personal` tools are machine-specific integrations. If those paths are not present on your machine, leave them out of `tools-manifest.json`.

### Adding your own tools

Drop a `.ps1` file into `tools/` following the `.CLAW_*` metadata convention, then add the tool name to `tools-manifest.json`:

```powershell
<#
.CLAW_NAME
    My-Tool
.CLAW_DESCRIPTION
    What this tool does and when Claude should use it.
.CLAW_RISK
    ReadOnly
.CLAW_CATEGORY
    SystemInfo
#>
function My-Tool {
    param(...)
    # implementation
}
```

Risk levels: `ReadOnly` (runs freely) · `Write` (requires confirmation prompt)

---

## Safety

- **Tool registry, not command generation.** Claude picks from approved tools only — it never writes raw PowerShell.
- **Write tools require confirmation.** Any tool with `CLAW_RISK = Write` pauses and asks Y/N before executing.
- **`-DryRun` mode.** Skips execution of write tools entirely.
- **`-Plan` mode.** Shows the first tool Claude would call (step-1 preview). Run without `-Plan` to execute all steps.
- **Output truncation.** Tool output is capped at `max_output_chars` (config.json) before being sent to the API.

---

## Configuration

`config.json` — model, token limits, max steps, API key env var name.

`tools-manifest.json` — the allowlist. Tools discovered on disk but not listed here are never loaded.

---

*Spec: PowerClaw-SPEC-v03.md · Built with PowerShell 7 + provider-configurable LLM backends*
