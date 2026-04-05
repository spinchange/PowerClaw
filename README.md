# PowerClaw

**PowerShell Command-Line Agentic Workbench** &nbsp;·&nbsp; [🌐 spinchange.github.io/PowerClaw](https://spinchange.github.io/PowerClaw/)

A Windows-native operations copilot for people who already live in PowerShell. You describe the task in plain English, PowerClaw picks from approved tools, runs the right Windows-native action, and returns a readable answer.

The model never generates raw PowerShell. It picks from a registry of approved, auditable tools you control.

Current release candidate: `v0.2.0`

---

## Best fit

PowerClaw is for:

- Windows power users who want faster local diagnostics without giving a model unrestricted shell access
- solo operators and technical builders who want plain-English access to services, logs, files, storage, and network state
- people who value inspectability, confirmation on writes, and a first-class Windows plus web investigation surface

If you want a general-purpose cross-platform agent shell, this repo is intentionally narrower than that.

## Top 3 workflows

1. **Machine triage**
   Ask for system health, CPU pressure, service failures, reboot timing, or recent event log warnings. PowerClaw now prefers a deterministic bounded system triage first, then follows up with narrower tools only when needed.
2. **File and storage cleanup**
   Find large files, inspect Downloads, locate old installers, and confirm before delete actions. PowerClaw now prefers a deterministic bounded cleanup summary first, then follows up only when the ranked candidates still look ambiguous. Cleanup answers call out what was found, what to review next, and which surfaced items are review-only versus execution-allowed after confirmation.
3. **Read and investigate**
   Summarize a webpage, inspect a local config or log, and connect what you read to system state. These prompts now default to a short evidence-backed summary instead of wandering through long multi-file or multi-page chains.

## Requirements

- PowerShell 7+
- .NET SDK (for the one-time `Fetch-WebPage` Playwright host setup)
- Anthropic or OpenAI API key
- Windows 10/11

## Setup

**1. Clone the repo**
```powershell
git clone https://github.com/spinchange/PowerClaw.git
cd PowerClaw
```

**2. Copy the starter config**
```powershell
Copy-Item .\config.example.json .\config.json
```

Or start from a provider-specific template:

```powershell
Copy-Item .\config.claude.example.json .\config.json
# or
Copy-Item .\config.openai.example.json .\config.json
```

Edit `config.json` for your provider, model, and API key env var.

**3. Set your API key**
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

**4. Import the module**
```powershell
Import-Module .\PowerClaw.psd1
```

This exports both `Invoke-PowerClaw` and the ergonomic alias `powerclaw`.

**5. Install the web runtime**
`Fetch-WebPage` is part of the default workbench surface, so install its runtime
with the supported one-command bootstrap:

```powershell
pwsh -File .\Install-PowerClawWebRuntime.ps1
```

This bootstraps the Playwright host project, builds it, and installs Chromium
for the default `Fetch-WebPage` tool.

If you want the underlying steps or a custom path, the installer script remains
small and readable.

**6. Validate setup**
```powershell
Test-PowerClawSetup
```

**7. Run first prompts**
```powershell
powerclaw "What's eating my CPU?"
powerclaw "Summarize https://news.ycombinator.com"
```

## Optional: Persistent local install

If you keep source repos under `C:\dev\repos`, install the module into a separate
PowerShell module root and install the `powerclaw.ps1` launcher into a bin directory:

```powershell
pwsh -File .\Install-PowerClaw.ps1 -ModuleRoot C:\dev\powershell-modules -BinRoot C:\dev\bin
```

The installer now copies the example configs and seeds `config.json` in the
installed module directory if one is not already present.

Then make sure:

- `C:\dev\powershell-modules` is on `PSModulePath`
- `C:\dev\bin` is on `PATH`

After that, `powerclaw` works as a real shell command in a new PowerShell session:

```powershell
# Run the installed web-runtime bootstrap once from the installed module directory
powerclaw "What's eating my CPU?"
```

---

## Usage

```powershell
# Workflow 1: machine triage
powerclaw "Give me a full system health check"
Invoke-SystemTriage | ConvertTo-Json -Depth 10

# Workflow 2: file and storage cleanup
powerclaw -Plan "Find the 10 biggest files in Downloads"
Invoke-CleanupSummary -Scope "$env:USERPROFILE\Downloads" | ConvertTo-Json -Depth 10

# Workflow 3: read and investigate
powerclaw "Read config.json and explain my settings"
powerclaw "Summarize https://learn.microsoft.com/powershell/"

# Safe testing without an API key
powerclaw -UseStub "What's eating my CPU?"
powerclaw -UseStub "Find the 10 biggest files in Downloads"
powerclaw -UseStub "Summarize https://news.ycombinator.com"

# Inspect the raw model traffic
powerclaw -Verbose "What's eating my CPU?"
```

For scripts or explicit PowerShell style, `Invoke-PowerClaw` remains available.

## Tests

PowerClaw now uses a Pester 5 suite.

Run the repo test suite with:

```powershell
pwsh -File .\Run-Tests.ps1
```

Run the opt-in live provider smoke check only when you intentionally want a real
network roundtrip:

```powershell
# Uses provider/model/api_key_env from config.json
pwsh -File .\tests\Test-LiveProviderSmoke.ps1

# Or verify both providers explicitly
pwsh -File .\tests\Test-LiveProviderSmoke.ps1 `
  -Provider both `
  -ClaudeModel claude-sonnet-4-20250514 `
  -OpenAiModel gpt-4.1-mini
```

If Pester 5.7.1 is not installed yet:

```powershell
Install-Module -Name Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
```

## Current release notes

`v0.2.0` is the current tag candidate for the first release that treats both
`system_triage` and `cleanup_summary` as formal local JSON document surfaces.

Highlights:
- deterministic `Invoke-SystemTriage` and `Invoke-CleanupSummary` reducers are now part of the exported module surface
- flagship health-check and cleanup prompts now prefer the deterministic local tools before broader provider-led exploration
- `system_triage` actions now include stable machine-readable `reason_code` values alongside human-readable `reason` text
- cleanup recommendations now expose ranked candidates plus `review_only` versus `execution_allowed` states
- delete safety is stricter around permanent intent, sensitive targets, and evidence-backed exact-path execution
- provider translation and loop behavior have stronger offline regression coverage, with live provider smoke kept opt-in

See [CHANGELOG.md](CHANGELOG.md) for the release entry and [docs/known-issues.md](docs/known-issues.md) for remaining limitations before or after tagging.

---

## Default tools

| Tool | Category | What it does |
|------|----------|-------------|
| `Get-SystemTriage` | SystemInfo | Deterministic bounded workstation-health triage across system, process, service, event, and storage signals |
| `Get-CleanupSummary` | Filesystem | Deterministic bounded cleanup summary with ranked candidates, candidate states, and the next safe action |
| `Get-SystemSummary` | SystemInfo | CPU, RAM, uptime, top processes |
| `Get-TopProcesses` | SystemInfo | Processes sorted by CPU or memory |
| `Get-EventLogEntries` | SystemInfo | Windows event log errors and warnings |
| `Get-ServiceStatus` | SystemInfo | Windows service health |
| `Get-NetworkStatus` | Network | Interfaces, connections, external IP |
| `Get-NetworkUsage` | Network | Per-process and connection-level network usage |
| `Get-StorageStatus` | Filesystem | Disk usage and largest folders |
| `Get-DirectoryListing` | Filesystem | List files in a directory |
| `Search-Files` | Filesystem | Windows Search index queries |
| `Read-FileContent` | Filesystem | Read and reason about any file |
| `Remove-Files` | Filesystem | Delete specific full-path files, with protected-root blocks, a default batch ceiling, single-file permanent delete, and evidence-backed target requirements |
| `Fetch-WebPage` | Web | Fetch readable webpage text from static or JavaScript-rendered pages |

`Fetch-WebPage` is part of the default workbench surface, but it depends on the
one-time runtime install handled by `Install-PowerClawWebRuntime.ps1`. Personal note-search tools such
as `Search-MyJoNotes` and `Search-MnVault` now live under `overlays\personal\`
so the main repo stays portable across machines.

To enable the personal overlay on one machine, copy the desired tool files from
`overlays\personal\tools\` into your active `tools\` directory and add their
names to your active `tools-manifest.json`.

Or use the helper script:

```powershell
pwsh -File .\Install-PowerClawOverlay.ps1 -OverlayName personal
```

That copies the overlay tools into the active `tools\` directory and updates the
active `tools-manifest.json` to approve them.

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

Risk levels: `ReadOnly` (runs freely) · `Write` (requires an explicit confirmation token)

---

## Safety

- **Tool registry, not command generation.** Claude picks from approved tools only — it never writes raw PowerShell.
- **Write tools require explicit confirmation.** Any tool with `CLAW_RISK = Write` pauses, shows arguments, and requires a typed confirmation token before executing.
- **Loop-level write policy.** Write tools are blocked unless the user goal explicitly asks for a destructive change. Advisory requests such as “what looks safe to remove?” stay read-only.
- **Evidence-backed delete policy.** `Remove-Files` only runs on exact full paths that were already shown earlier in the same request by a read-only tool. The model cannot jump straight from a vague delete request to an unverified path.
- **Destructive path policy.** `Remove-Files` requires fully qualified file paths, blocks deletion from Windows, System, Program Files, and ProgramData locations, caps delete batches by default, and allows permanent delete for only one file per call.
- **`-DryRun` mode.** Skips execution of write tools entirely.
- **`-Plan` mode.** Shows a short intended tool chain preview before execution. Run without `-Plan` to execute the steps for real.
- **Output truncation.** Tool output is capped at `max_output_chars` (config.json) before being sent to the API.
- **Structured loop logs.** Each step writes structured append-only log entries with stable event/outcome pairs for requests, previews, blocks, declines, confirmations, executions, final answers, and aborts.

### Loop log v1

PowerClaw now emits versioned `loop_log` v1 JSON lines for structured loop
logging.

- always present: `SchemaVersion`, `Kind`, `Timestamp`, `Event`, `Outcome`, `Step`
- stable event/outcome pairs now define the meaning of request, preview, block,
  decline, confirmation, execution, final-answer, and abort entries
- normalized `PolicyReason` values now cover write-boundary decisions, and
  normalized `ControlReason` values now cover repeated-call, plan-preview, and
  latency-budget control paths
- event-specific fields are defined in [docs/loop-log-v1.md](docs/loop-log-v1.md)
  with the matching schema in [docs/loop-log-v1.schema.json](docs/loop-log-v1.schema.json)

---

## Configuration

`config.json` — model, token limits, max steps, API key env var name.

`config.claude.example.json` / `config.openai.example.json` — clean starting points for each supported provider.

`tools-manifest.json` — the allowlist. Tools discovered on disk but not listed here are never loaded.

`overlays\personal\` — optional machine-specific tools and an overlay manifest example.

`Install-PowerClawOverlay.ps1` — helper to install an overlay into an active repo or installed module tree.

`Install-PowerClawWebRuntime.ps1` — supported one-command installer for the default `Fetch-WebPage` runtime.

---

*Spec: PowerClaw-SPEC-v03.md · Built with PowerShell 7 + provider-configurable LLM backends*
