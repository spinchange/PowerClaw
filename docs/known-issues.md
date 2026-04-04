# PowerClaw Known Issues

Current limitations, rough edges, and deferred problems that are real enough to
track but not yet resolved.

## Current issues

### `Fetch-WebPage` has heavy local prerequisites

It depends on a separate Playwright setup flow and browser install.

Impact:
- useful capability, but not zero-setup
- can fail on machines without the documented runtime

### Provider live roundtrip coverage is still manual

The automated suite covers provider payload translation and parsing offline, but
does not exercise live Anthropic or OpenAI calls by default.

Impact:
- safer refactors
- but live API compatibility still needs occasional manual verification

### Write-tool safety is confirmation-based, not policy-rich

Destructive tools rely on confirmation prompts and tool-level discipline.

Impact:
- acceptable for the current scope
- not sufficient for more advanced automation scenarios

### Personal integrations remain repo-resident

Machine-specific tools exist in the main repo, even though they are disabled by default.

Impact:
- convenient for one-machine customization
- still mixes portable and personal concerns in one codebase

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
