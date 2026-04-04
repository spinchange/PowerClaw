# PowerClaw Decisions

Durable product and implementation decisions for this repo.

## Current decisions

### Product position: Windows-native operations workbench

PowerClaw is positioned as a Windows-first personal operations workbench, not a
general cross-platform agent shell.

Why:
- the strongest differentiator is deep Windows usefulness
- the product story is clearer when it leans into native OS strengths
- it avoids competing on generic “agent framework” terms alone

### Primary user fit: Windows power users and technical solo operators

The primary ICP is users who already work comfortably in PowerShell and want
plain-English help with local machine operations, without giving a model
unconstrained shell access.

Why:
- matches the trust-first product design
- aligns with the strongest current workflow set: diagnostics, cleanup, and investigation
- keeps onboarding focused on high-value local tasks instead of generic agent claims

### Tool registry instead of arbitrary command generation

PowerClaw allows the model to select only from approved PowerShell tools.
It does not allow free-form PowerShell generation.

Why:
- keeps execution auditable
- narrows the safety surface
- makes provider behavior easier to reason about and test

### Manifest-controlled tool loading

`tools-manifest.json` is the source of truth for what can register.
Tools must be approved to load, and tools listed in `disabled_tools` must not load
even if also present in `approved_tools`.

Why:
- supports safe defaults
- lets machine-specific tools exist in-repo without being enabled everywhere

### Strict tool schemas

Generated tool schemas set `additionalProperties = false`.

Why:
- prevents invented arguments from the model
- pushes invalid input rejection earlier into the tool-selection contract

### Portable defaults over machine-specific defaults

Personal integrations such as `Search-MyJoNotes` and `Search-MnVault` should live
in an optional overlay rather than the main portable tool directory.

Why:
- the default repo should work on any Windows machine with minimal surprises
- personal integrations are valid, but should be opt-in
- the portable core is clearer when machine-specific tools are physically separate

### Provider choice is implementation detail, not primary product identity

PowerClaw can support multiple LLM providers, but the core product promise is the
tool-registry execution model on Windows, not allegiance to one vendor.

Why:
- keeps the product story stable as providers change
- keeps docs and roadmap focused on user outcomes instead of backend branding
- reduces unnecessary coupling between product identity and model vendor

### Pester 5 is the primary test framework

The supported automated test entrypoint is `pwsh -File .\Run-Tests.ps1`, using
Pester `5.7.1+`.

Why:
- gives the repo a single supported test command
- supports offline mocking for provider logic
- improves maintainability over ad hoc script checks alone

### Offline provider regression coverage is required

Provider translation tests should mock `Invoke-RestMethod` rather than depending
on live network calls or live API keys.

Why:
- keeps default verification fast and deterministic
- makes provider changes safer to refactor

### Minimal structured log contract is a supported surface

PowerClaw supports a small stable subset of the loop log schema for inspection
and lightweight tooling.

Supported fields on every log entry:
- `SchemaVersion`
- `Timestamp`
- `Event`
- `Outcome`
- `Step`

Additionally supported when present for tool-related entries:
- `Tool`
- `ToolUseId`
- `Reason`

Other fields such as previews, argument payloads, result lengths, and timing are
useful but not yet part of the supported contract.

Why:
- makes inspectability real without freezing the whole log payload too early
- gives downstream tooling a small stable target
- preserves freedom to refine non-core fields while execution behavior evolves

## Update rule

Add an entry here when:
- a behavior contract changes
- a new safety boundary is introduced
- a default repo policy changes
- a major architectural tradeoff is intentionally chosen

Do not use this file for temporary task notes or session logs.
