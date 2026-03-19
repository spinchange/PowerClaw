# PowerClaw

**PowerShell Command-Line Agentic Workbench** &nbsp;·&nbsp; [🌐 spinchange.github.io/PowerClaw](https://spinchange.github.io/PowerClaw/)

A Windows-native agentic automation framework built on PowerShell 7. You describe what you want in plain English — PowerClaw uses Claude to pick the right tool, runs it on your machine, and returns a human-readable answer.

Claude never generates raw PowerShell. It picks from a registry of approved, auditable tools you control.

---

## Requirements

- PowerShell 7+
- [Anthropic API key](https://console.anthropic.com)
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

**3. Import the module**
```powershell
Import-Module .\PowerClaw.psd1
```

**4. Run a prompt**
```powershell
Invoke-PowerClaw -Prompt "What are the top 5 processes by memory?"
```

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
Invoke-PowerClaw -Prompt "Give me a full system health check"

# See what Claude would do without running it
Invoke-PowerClaw -Plan -Prompt "Find the 10 biggest files in Downloads"

# Test without an API key
Invoke-PowerClaw -UseStub -Prompt "anything"

# Verbose — see full request/response JSON
Invoke-PowerClaw -Verbose -Prompt "What's eating my CPU?"
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

*Spec: PowerClaw-SPEC-v03.md · Built with PowerShell 7 + Claude API*
