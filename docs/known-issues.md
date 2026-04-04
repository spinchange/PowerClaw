# PowerClaw Known Issues

Current limitations, rough edges, and deferred problems that are real enough to
track but not yet resolved.

## Current issues

### `Fetch-WebPage` onboarding still depends on extra local runtime setup

`Fetch-WebPage` is part of the default workbench surface again, and now has a
supported one-command installer, but it still depends on a local Playwright
runtime and browser install.

Impact:
- core product value still depends on an extra runtime dependency
- can still fail in constrained hosts that block headless browser launch, even after install

### Provider live roundtrip coverage is still manual

The automated suite covers provider payload translation and parsing offline, and
the repo now includes an opt-in live smoke script, but real Anthropic and OpenAI
calls are still not exercised by default CI or the default local suite.

Impact:
- safer refactors
- but live API compatibility still needs occasional manual verification

### Write-tool safety is confirmation-based, not policy-rich

Destructive tools now require an explicit typed confirmation token, but still rely
primarily on confirmation and tool-level discipline rather than richer policy
controls.

Impact:
- acceptable for the current scope
- improved by loop-level blocking when the user did not explicitly ask for a destructive change
- improved by path-policy checks on `Remove-Files`
- improved by default batch ceilings and single-file permanent delete limits
- not sufficient for more advanced automation scenarios

### Structured loop logs are clearer than their current contract

The loop now emits structured per-step log entries with explicit event/outcome
pairs for blocked, declined, confirmed, executed, and final-answer paths, and a
minimal supported subset now exists. The remaining limitation is that the full
event schema is still not treated as a formally versioned product surface.

Impact:
- useful for debugging and inspection today
- less ambiguous than before for write-path analysis
- but downstream tooling or user expectations could still become fragile if the shape changes casually

### Default product narrative is stronger than the current docs architecture

The product has a clear trust-and-Windows-native story, but roadmap and supporting
docs can drift back toward engineering-task language if not maintained deliberately.

Impact:
- priorities can become implementation-led instead of product-led
- future contributors may optimize for code health without strengthening the product

## Update rule

Add an issue here when:
- it affects users or contributors repeatedly
- it is accepted as unresolved for now
- it needs visibility outside a single session

Remove or rewrite entries when they stop being true.
