# Changelog

## v0.2.0 - 2026-04-04

Tag candidate: `v0.2.0`

First release candidate for PowerClaw as a Windows-native command-line
workbench with deterministic local reducers, stricter write safety, and a
clearer product shape around machine triage, cleanup, and investigation.

Highlights:

- added deterministic local reducers for both flagship workflows:
  `Invoke-SystemTriage` / `Get-SystemTriage` for workstation health, and
  `Invoke-CleanupSummary` / `Get-CleanupSummary` for cleanup review
- formalized bounded JSON document contracts under `docs/` for
  `system_triage`, `cleanup_summary`, and `loop_log`
- tightened `system_triage` action semantics with stable machine-readable
  `reason_code` values plus producer-side validation of canonical action
  templates
- strengthened cleanup outputs with explicit ranking, clearer ambiguity
  guidance, and `review_only` versus `execution_allowed` candidate states
- tightened destructive-write safety so delete actions require stronger intent,
  more specific references for higher-risk targets, and evidence-backed exact
  paths
- improved release-facing docs so the README, known issues, and roadmap more
  clearly describe the current product surface and remaining limitations
