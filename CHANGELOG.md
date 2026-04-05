# Changelog

## v0.2.0 - 2026-04-04

Tag candidate: `v0.2.0`

- added deterministic `cleanup_summary` production via `Invoke-CleanupSummary` and the approved read-only `Get-CleanupSummary` tool
- exported `Invoke-CleanupSummary` from the module and routed flagship cleanup workflows to prefer the deterministic summary first
- formalized the `cleanup_summary` v1 document and schema under `docs/`
- strengthened cleanup answer shaping with explicit ranking, ambiguity guidance, and `review_only` versus `execution_allowed` candidate states
- tightened delete safety so permanent deletion requires explicit permanent intent and higher-risk targets require more specific user reference
- documented the current deterministic workflow surfaces and release-state limitations more explicitly
