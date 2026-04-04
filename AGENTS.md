# PowerClaw Agent Notes

Repo-specific guidance for contributors and coding agents working in `C:\dev\repos\PowerClaw`.

## Purpose

PowerClaw is a Windows-native PowerShell module for LLM-guided tool orchestration.
The model does not generate arbitrary PowerShell. It selects from approved tools
defined in `tools/` and allowed by `tools-manifest.json`.

## Repo map

- `PowerCLAW.psd1`
  Module manifest.
- `PowerCLAW.psm1`
  Module entrypoint and dot-sourcing order.
- `powerclaw.ps1`
  Lightweight launcher for shell-first usage.
- `core/`
  User-facing command and multi-step execution loop.
- `client/`
  Provider dispatcher and provider-specific HTTP adapters.
- `registry/`
  Tool discovery, manifest filtering, and JSON schema generation.
- `tools/`
  Approved callable tools. Each tool is its own `.ps1` file.
- `tests/`
  Pester suite and legacy script-style regression tests.
- `Run-Tests.ps1`
  Supported repo test entrypoint.

## Primary commands

Run the supported test suite:

```powershell
pwsh -File .\Run-Tests.ps1
```

Run a stubbed end-to-end invocation:

```powershell
pwsh -NoProfile -Command "Import-Module .\PowerCLAW.psd1 -Force; powerclaw -UseStub 'What are the top 5 processes by memory?'"
```

Run the launcher directly from the repo root:

```powershell
pwsh -NoProfile -File .\powerclaw.ps1 -UseStub "anything"
```

## Test policy

- Prefer `Run-Tests.ps1` over invoking individual test files directly.
- The intended framework is Pester `5.7.1` or newer.
- `Run-Tests.ps1` is written to work in constrained environments by disabling
  Pester `TestRegistry`.
- Keep fast offline tests for provider translation, registry behavior, and tool
  semantics. Avoid making the default suite depend on live API keys or network calls.

## Tool contract

When adding or editing a tool:

1. Add a single `.ps1` file under `tools/`.
2. Include `.CLAW_NAME`, `.CLAW_DESCRIPTION`, and `.CLAW_RISK` metadata.
3. Keep parameters explicit and schema-friendly.
4. Prefer safe defaults and literal path handling for filesystem operations.
5. Return structured objects rather than formatted text when practical.

## Manifest rules

- `tools-manifest.json` is the source of truth for what can load.
- Tools must be in `approved_tools` to register.
- Tools in `disabled_tools` must not register, even if also approved.
- Personal or machine-specific tools should stay disabled by default unless this
  repo is intentionally being customized for one machine.

## Provider rules

- Preserve the canonical internal response shape:
  `tool_call` or `final_answer`.
- Keep provider tests offline by mocking `Invoke-RestMethod`.
- If provider payload translation changes, update Pester coverage in
  `tests/PowerClaw.Tests.ps1`.

## Safety expectations

- Do not weaken the tool-registry model by introducing arbitrary command generation.
- Write tools should require confirmation through the loop unless explicitly
  designed otherwise.
- Keep schemas strict. `additionalProperties` should remain disabled so the model
  cannot invent unsupported arguments.

## Done criteria

A change in this repo is not done until:

1. `pwsh -File .\Run-Tests.ps1` passes.
2. Any changed behavior has regression coverage when reasonable.
3. README and manifest/docs are updated if the user-facing behavior changed.
