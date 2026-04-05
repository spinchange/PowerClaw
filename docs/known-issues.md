# PowerClaw Known Issues

Current limitations, rough edges, and deferred problems that are real enough to
track but not yet resolved.

## Current issues for `v0.2.0`

These issues remain open for the current `v0.2.0` tag candidate.

### `Fetch-WebPage` onboarding still depends on extra local runtime setup

`Fetch-WebPage` is part of the default workbench surface again, and now has a
supported one-command installer, but it still depends on a local Playwright
runtime and browser install.

Impact:
- core product value still depends on an extra runtime dependency
- can still fail in constrained hosts that block headless browser launch, even after install

### Provider live verification is still opt-in rather than part of default verification

The automated suite now covers provider payload translation, follow-up
`tool_result` roundtrips, deterministic reducer flows, and an opt-in live smoke
path more thoroughly than before. Both Claude and OpenAI live smoke have now
been verified successfully, but that live verification is still not part of
default CI or the default local suite.

Impact:
- safer refactors
- both provider adapters now have credible live verification
- but provider compatibility can still drift later unless someone reruns the opt-in smoke checks
- provider setup failures can still look like product breakage until diagnosed

### Real answer quality still depends too much on provider behavior outside deterministic reducers

Flagship workflows now have deterministic first-pass reducers for system triage
and cleanup plus better planning and stronger final-answer guidance, but the
real provider-backed experience can still vary more than the product should
ultimately tolerate outside those bounded paths.

Impact:
- answers are usually more product-shaped than before
- cleanup and investigation now have stronger enforced answer shaping than before
- but multi-tool synthesis quality is still partly prompt-led rather than reducer-driven
- occasional weak summaries or under-integrated final answers are still plausible

### Write-tool safety is stronger, but still not fully policy-rich

Destructive tools now require an explicit typed confirmation token, but still rely
partly on confirmation and tool-level discipline rather than richer end-to-end
policy controls.

Impact:
- acceptable for the current scope
- improved by loop-level blocking when the user did not explicitly ask for a destructive change
- improved by path-policy checks on `Remove-Files`
- improved by default batch ceilings and single-file permanent delete limits
- improved by explicit permanent-delete intent checks and more specific reference requirements for higher-risk target classes
- improved by cleanup answers that now surface review-only versus execution-allowed candidate states before deletion
- not sufficient for more advanced automation scenarios

### Structured loop logs are versioned, but still intentionally narrow

The loop now emits versioned `loop_log` v1 entries with a formal schema and
explicit event/outcome pairs plus normalized `PolicyReason` and
`ControlReason` vocabularies. The remaining limitation is that the contract is
still intentionally narrow and does not yet try to freeze every preview or
payload detail as a long-term product surface.

Impact:
- useful for debugging and inspection today
- less ambiguous than before for write-path analysis and event interpretation
- but downstream tooling should still avoid depending on every optional payload field

### Product-documentation alignment still requires deliberate maintenance

The main README and homepage are now materially more aligned than before, but
supporting docs can still drift back toward engineering-task language if not
maintained deliberately.

Impact:
- priorities can become implementation-led instead of product-led
- future contributors may optimize for code health without strengthening the product

## Update rule

Add an issue here when:
- it affects users or contributors repeatedly
- it is accepted as unresolved for now
- it needs visibility outside a single session

Remove or rewrite entries when they stop being true.
