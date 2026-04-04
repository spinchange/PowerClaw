# System Triage V1

Normative specification for a bounded `system_triage` JSON document intended for local agent-efficient workstation-health reasoning on Windows.

## Purpose

The producer emits one JSON document summarizing the top health issues on one Windows workstation host using current collector state plus recent service and event context from the last 60 minutes.

The document answers:
- what is wrong
- how serious it is
- why the producer believes it
- what to inspect next
- which collectors produced the evidence

The document does not:
- store raw telemetry or full logs
- perform remediation
- model multiple hosts
- expose arbitrary telemetry
- include extension points or custom per-install fields

V1 is intentionally scoped to a single-user Windows workstation, not arbitrary server or fleet environments.

## Fixed V1 decisions

These decisions are frozen for v1:
- `window_minutes` is fixed at `60`
- `unstable_service` uses a fixed allowlist of important services
- `repeated_system_errors` uses fixed thresholds
- `abnormal_uptime_signal` may only appear if at least one other finding exists

## Schema scope

The JSON Schema for v1 validates local structure, field presence, enums, and length caps.

Cross-field invariants such as:
- finding ID uniqueness
- action priority uniqueness
- `source_refs` resolution
- `related_finding_ids` resolution
- `summary.status` consistency
- `summary.score` consistency

remain producer-side validation requirements rather than pure schema guarantees in v1.

## Allowed collectors

Only these collectors may contribute evidence in v1:
- `Get-SystemSummary`
- `Get-TopProcesses`
- `Get-ServiceStatus`
- `Get-EventLogEntries`
- `Get-StorageStatus`

No other collectors may contribute to the v1 document.

## Top-level document

The document must contain exactly these top-level fields and no others:

```json
{
  "schema_version": "1.0",
  "kind": "system_triage",
  "host": "ws-01",
  "captured_at": "2026-04-04T18:05:00-05:00",
  "window_minutes": 60,
  "summary": {},
  "findings": [],
  "actions": [],
  "sources": []
}
```

Rules:
- `schema_version` must equal `1.0`
- `kind` must equal `system_triage`
- `host` must be a string of 1-64 chars
- `captured_at` must be an ISO 8601 timestamp with offset
- `window_minutes` must equal `60`
- `summary` must be an object
- `findings` must be an array with at most 10 items
- `actions` must be an array with at most 5 items
- `sources` must be an array with at most 12 items

## Summary

`summary` must have exactly these fields:

```json
{
  "status": "warning",
  "score": 62,
  "headline": "Memory pressure is elevated and one service appears unstable"
}
```

Rules:
- `status` must be one of `ok|info|warning|critical`
- `score` must be an integer from `0` to `100`
- `headline` must be a string of 1-120 chars
- `status` must reflect the highest severity present in `findings`
- if `findings` is empty, `status` must be `ok`
- `headline` must be readable in isolation and must not exceed one sentence

## Findings

Each item in `findings` must have exactly these fields:

```json
{
  "id": "high_memory:global",
  "type": "high_memory",
  "severity": "warning",
  "category": "memory",
  "title": "Memory usage is elevated",
  "reason": "RAM usage remained above threshold during the observation window",
  "evidence": [
    "Memory in use: 87%",
    "Top memory process: Code at 842 MB"
  ],
  "confidence": 0.91,
  "source_refs": ["src_system", "src_processes"]
}
```

Rules:
- `id` must be a deterministic string of 1-80 chars
- `type` must be one of:
  - `high_cpu`
  - `high_memory`
  - `low_disk`
  - `unstable_service`
  - `repeated_system_errors`
  - `abnormal_uptime_signal`
- `severity` must be one of `info|warning|critical`
- `category` must be one of `cpu|memory|disk|service|eventlog|uptime`
- `title` must be a string of 1-100 chars
- `reason` must be a string of 1-220 chars
- `evidence` must contain 1-3 strings, each 1-120 chars
- `confidence` must be a number from `0.0` to `1.0`
- `source_refs` must contain 1-3 IDs present in `sources`
- findings must be sorted by severity descending, then confidence descending
- no two findings may share the same `id`

## Actions

Each item in `actions` must have exactly these fields:

```json
{
  "id": "inspect_memory_top_processes",
  "priority": 1,
  "kind": "inspect",
  "target": "processes",
  "reason": "Memory pressure is elevated and the top consumers should be reviewed",
  "related_finding_ids": ["high_memory:global"]
}
```

Rules:
- `id` must be a string of 1-80 chars
- `priority` must be a unique integer from `1` to `5`
- `kind` must be one of `inspect|confirm|ignore|monitor|escalate`
- `target` must be a string of 1-80 chars
- `reason` must be a string of 1-160 chars
- `related_finding_ids` must contain 1-3 finding IDs present in `findings`
- actions must be sorted by ascending `priority`

V1 action constraints:
- actions must recommend inspection, confirmation, monitoring, or escalation only
- actions must not encode write operations
- actions must not recommend delete, restart, kill, stop, or modify operations

## Sources

Each item in `sources` must have exactly these fields:

```json
{
  "id": "src_system",
  "tool": "Get-SystemSummary",
  "captured_at": "2026-04-04T18:04:32-05:00",
  "scope": "local_host"
}
```

Rules:
- `id` must be a string of 1-40 chars
- `tool` must be one of:
  - `Get-SystemSummary`
  - `Get-TopProcesses`
  - `Get-ServiceStatus`
  - `Get-EventLogEntries`
  - `Get-StorageStatus`
- `captured_at` must be an ISO 8601 timestamp with offset
- `scope` must be a string of 1-80 chars
- source objects must not embed raw payloads

## Important service allowlist

Only these workstation-relevant services may generate `unstable_service` in v1:
- `LanmanServer`
- `Dnscache`
- `EventLog`
- `WinDefend`
- `W32Time`
- `wuauserv`
- `Spooler`

## Finding rules

### `high_cpu`

- category must be `cpu`
- severity must be:
  - `warning` if overall CPU is `>= 70` and `< 90`
  - `critical` if overall CPU is `>= 90`
- evidence should include current overall CPU and the top CPU process if available
- reason and evidence must not imply the threshold was sustained across the full 60-minute window unless a future collector explicitly supports that claim
- ID must be `high_cpu:global`

### `high_memory`

- category must be `memory`
- severity must be:
  - `warning` if memory usage is `>= 80` and `< 92`
  - `critical` if memory usage is `>= 92`
- evidence should include current memory percent and top memory process if available
- reason and evidence must not imply the threshold was sustained across the full 60-minute window unless a future collector explicitly supports that claim
- ID must be `high_memory:global`

### `low_disk`

- category must be `disk`
- severity must be:
  - `warning` if free space on any monitored volume is `<= 20%` and `> 10%`
  - `critical` if free space is `<= 10%`
- only the most severe volume may emit a finding in v1
- ID must be `low_disk:<volume>` using lowercase drive letter without colon

### `unstable_service`

- category must be `service`
- emitted only for services in the fixed allowlist
- severity must be:
  - `warning` if one allowed service is stopped unexpectedly or has one recent failure signal
  - `critical` if one allowed service has repeated failures or if multiple allowed services are unstable
- for v1, `repeated failures` means `failure_count >= 2`
- IDs must be deterministic, for example `unstable_service:spooler`

### `repeated_system_errors`

- category must be `eventlog`
- severity must be:
  - `warning` if warning/error count from the dominant source is `>= 5` within 60 minutes
  - `critical` if error count from the dominant source is `>= 10` within 60 minutes
- only one dominant-source finding may be emitted in v1
- ID must be `repeated_system_errors:<source>` normalized to lowercase with spaces replaced by `_`

### `abnormal_uptime_signal`

- category must be `uptime`
- may be emitted only if at least one other finding exists
- severity must be:
  - `info` if uptime is `< 2 hours`
  - `warning` if uptime is `> 30 days` and another finding exists
- it must never be `critical`
- ID must be `abnormal_uptime_signal:global`

## Scoring

Score must be computed mechanically:
- start at `0`
- add `20` for each `warning` finding
- add `40` for each `critical` finding
- ignore `info` findings for score
- cap at `100`

## Status derivation

`summary.status` must be derived as follows:
- `critical` if any finding is `critical`
- else `warning` if any finding is `warning`
- else `info` if any finding is `info`
- else `ok`

## Output reduction rules

If more potential findings exist than v1 allows:
- keep highest severity first
- then highest confidence
- then highest actionability
- discard the rest

If more than one `low_disk` candidate exists:
- keep only the most severe volume

If more than one event-log source qualifies:
- keep only the dominant source by count

## Producer contract

The producer must:
- invoke only the five allowed collectors
- normalize their outputs into a fixed internal shape
- evaluate the six finding rules deterministically
- reduce overflow deterministically
- derive actions deterministically
- emit one valid JSON document conforming to the v1 schema

The producer must not:
- invent data not present in collector output
- emit unbounded raw payloads
- include optional fields outside the schema
- perform writes or remediations
- vary behavior by model, provider, or user prompt in v1

### Execution contract

The producer must run the collectors in this logical order:
1. `Get-SystemSummary`
2. `Get-TopProcesses`
3. `Get-ServiceStatus`
4. `Get-EventLogEntries`
5. `Get-StorageStatus`

The producer may execute them in parallel, but the output must behave as if evaluated in the above order.

If a collector fails:
- record no source entry for that collector
- skip any finding types that require it
- continue producing the document if at least `host`, `captured_at`, and `summary` can still be emitted

If all finding-relevant collectors fail:
- emit a valid document with empty `findings` and `actions`
- `summary.status` must be `ok`
- `summary.score` must be `0`
- `summary.headline` should say no abnormal signals were derived from available collectors

### Internal normalized input shape

Before rule evaluation, the producer must normalize collector outputs into this internal shape:

```json
{
  "host": "ws-01",
  "captured_at": "2026-04-04T18:05:00-05:00",
  "system": {
    "cpu_pct": 18.0,
    "memory_pct": 63.0,
    "uptime_hours": 102.5
  },
  "top_processes": {
    "cpu": {
      "name": "Code",
      "cpu_pct": 9.4
    },
    "memory": {
      "name": "Code",
      "mem_mb": 842
    }
  },
  "volumes": [
    {
      "name": "C",
      "free_pct": 12.4,
      "free_gb": 48.2,
      "kind": "fixed",
      "is_system": true
    }
  ],
  "services": [
    {
      "name": "Spooler",
      "state": "running",
      "startup": "automatic",
      "recent_failure_signal": true,
      "failure_count": 2
    }
  ],
  "event_sources": [
    {
      "source": "Service Control Manager",
      "warning_error_count": 6,
      "error_count": 4
    }
  ]
}
```

Any missing value must be represented as absent or null internally, not as invented defaults.

### Normalization rules by collector

#### `Get-SystemSummary`

The producer must extract:
- host name
- capture time if available, otherwise producer capture time
- overall CPU percent as `cpu_pct`
- overall memory percent as `memory_pct`
- uptime as `uptime_hours`

The producer must normalize:
- percentages to `0-100`
- uptime to decimal hours
- host to a plain string without domain unless only FQDN is available

If `cpu_pct`, `memory_pct`, or `uptime_hours` are unavailable, the relevant rules must not emit.

#### `Get-TopProcesses`

The producer must identify:
- one top CPU process
- one top memory process

The producer must normalize:
- CPU to percent
- memory to MB
- process names to display-safe strings

If multiple candidates tie:
- prefer higher metric value
- then higher working set for memory ties
- then alphabetical process name

#### `Get-StorageStatus`

The producer must normalize local fixed volumes into:
- `name`
- `free_pct`
- `free_gb`
- `kind`
- `is_system`

The producer must exclude:
- removable volumes
- network volumes
- optical or media volumes
- volumes without a stable drive name

#### `Get-ServiceStatus`

The producer must normalize services into:
- `name`
- `state`
- `startup`
- `recent_failure_signal`
- `failure_count`

`recent_failure_signal` may be inferred from:
- direct service collector failure or restart metadata
- corroborating recent event-log evidence tied to the service

Startup normalization must map to:
- `automatic`
- `manual`
- `disabled`
- `unknown`

State normalization must map to:
- `running`
- `stopped`
- `paused`
- `other`

#### `Get-EventLogEntries`

The producer must group events into `event_sources[]` by normalized source name.

For each source:
- `warning_error_count` equals warnings plus errors in the last 60 minutes
- `error_count` equals errors only in the last 60 minutes

Source name normalization:
- trim whitespace
- collapse repeated spaces
- preserve display form for evidence text
- lowercase and underscore only when deriving IDs

If event log messages mention allowlisted services, the producer may use that to corroborate `recent_failure_signal`.

### Finding construction templates

#### `high_cpu`

Title:
- warning: `CPU usage is elevated`
- critical: `CPU usage is critical`

Reason:
- warning: `Current CPU usage is above the warning threshold`
- critical: `Current CPU usage is above the critical threshold`

Evidence templates:
- required: `CPU in use: {cpu_pct}%`
- optional: `Top CPU process: {name} at {cpu_process_pct}%`

Source refs:
- always include system source
- include process source if second evidence line is used

Confidence:
- fixed `0.95`

#### `high_memory`

Title:
- warning: `Memory usage is elevated`
- critical: `Memory usage is critical`

Reason:
- warning: `Current memory usage is above the warning threshold`
- critical: `Current memory usage is above the critical threshold`

Evidence templates:
- required: `Memory in use: {memory_pct}%`
- optional: `Top memory process: {name} at {mem_mb} MB`

Source refs:
- always include system source
- include process source if second evidence line is used

Confidence:
- fixed `0.95`

#### `low_disk`

Title:
- `Disk free space is low on {volume}`

Reason:
- warning: `Available disk space on the selected volume is below the warning threshold`
- critical: `Available disk space on the selected volume is below the critical threshold`

Evidence templates:
- required: `Volume {volume} free space: {free_pct}%`
- optional: `Free space remaining: {free_gb} GB`

Source refs:
- storage source only

Confidence:
- fixed `0.98`

#### `unstable_service`

Single-service title:
- `{service} appears unstable`

Rolled-up title:
- `Multiple important services appear unstable`

Single-service reason:
- warning: `The service showed a recent instability signal during the observation window`
- critical: `The service showed repeated instability signals during the observation window`

Rolled-up reason:
- `More than one important service showed instability during the observation window`

Evidence templates, single service:
- `Service state: {state}`
- optional `Recent failure signals: {failure_count}`
- optional corroboration `Recent service-related event activity was observed`

Evidence templates, rolled-up:
- `Unstable important services: {count}`
- `Affected services: {name1}, {name2}`

Source refs:
- always include service source
- include event source when corroboration is used

Confidence:
- `0.80` if only direct service-state anomaly
- `0.85` if one corroborating signal exists
- `0.90` if repeated failure count and corroboration exist

#### `repeated_system_errors`

Title:
- `Recent system errors are concentrated in {source}`

Reason:
- warning: `Warning and error activity from one source exceeded the warning threshold`
- critical: `Repeated error-level activity from one source exceeded the critical threshold`

Evidence templates:
- required: `{warning_error_count} warnings/errors from {source} in 60 minutes`
- optional: `{error_count} were error-level events`

Source refs:
- event source only

Confidence:
- `0.70` if based only on warning and error total
- `0.85` if critical due to repeated error-level events

#### `abnormal_uptime_signal`

Title:
- `System uptime may explain current conditions`

Reason:
- info: `The system restarted recently and some current signals may be post-boot effects`
- warning: `Extended uptime may be contributing to current instability signals`

Evidence templates:
- recent reboot: `Current uptime: {uptime_hours} hours`
- long uptime: `Current uptime: {uptime_days} days`

Source refs:
- system source only

Confidence:
- fixed `0.90`

### Deterministic ID contract

The producer must derive IDs exactly as follows:
- `high_cpu:global`
- `high_memory:global`
- `low_disk:{drive-letter-lowercase}`
- `unstable_service:{service-name-lowercase}`
- `unstable_service:multiple`
- `repeated_system_errors:{normalized-source}`
- `abnormal_uptime_signal:global`

Normalization for service and source ID segments:
- lowercase
- trim outer whitespace
- replace internal whitespace runs with `_`
- remove `:`
- keep only ASCII letters, digits, `_`, and `-` where practical

### Source entry contract

The producer must create at most one source entry per collector invocation.

Recommended IDs:
- `src_system`
- `src_processes`
- `src_storage`
- `src_services`
- `src_events`

Recommended scopes:
- `local_host`
- `top_processes`
- `fixed_volumes`
- `important_services`
- `last_60_minutes`

If a collector does not contribute to any emitted evidence, the producer may still include its source entry if it ran successfully, but should not exceed source caps.

### Reduction and tie-break contract

When multiple candidate findings of the same family exist:

`low_disk`
- keep only the most severe volume
- tie-break by lower `free_pct`
- then lower `free_gb`
- then system volume
- then alphabetical volume name

`unstable_service`
- if 2 or more allowlisted services qualify, prefer one rolled-up critical finding
- do not emit separate warnings for those same services in v1

`repeated_system_errors`
- choose dominant source by highest `warning_error_count`
- then highest `error_count`
- then alphabetical normalized source name

Overall overflow reduction:
- severity descending
- confidence descending
- actionability descending using this fixed order:
  - `low_disk`
  - `unstable_service`
  - `high_memory`
  - `high_cpu`
  - `repeated_system_errors`
  - `abnormal_uptime_signal`

### Action construction contract

The producer must generate actions from emitted findings only.

Default action templates:
- `high_cpu`
  - `id`: `inspect_cpu_processes`
  - `kind`: `inspect`
  - `target`: `processes`
  - `reason`: `Review the top CPU consumers to identify avoidable load`
- `high_memory`
  - `id`: `inspect_memory_top_processes`
  - `kind`: `inspect`
  - `target`: `processes`
  - `reason`: `Review the top memory consumers to identify avoidable pressure`
- `low_disk`
  - `id`: `inspect_volume_{volume}`
  - `kind`: `inspect`
  - `target`: `volume:{volume}`
  - `reason`: `Review large consumers on the affected volume before space becomes critical`
- `unstable_service` single
  - `id`: `confirm_{service}_stability`
  - `kind`: `confirm`
  - `target`: `service:{service}`
  - `reason`: `Confirm whether the service instability is ongoing or user-impacting`
- `unstable_service` rolled-up
  - `id`: `escalate_service_instability`
  - `kind`: `escalate`
  - `target`: `services`
  - `reason`: `Multiple important services show instability and should be reviewed together`
- `repeated_system_errors`
  - `id`: `inspect_event_source_{source}`
  - `kind`: `inspect`
  - `target`: `event_source:{source}`
  - `reason`: `Review repeated recent errors from the dominant event source`
- `abnormal_uptime_signal`
  - `id`: `monitor_uptime_context`
  - `kind`: `monitor`
  - `target`: `uptime`
  - `reason`: `Track whether current signals change as uptime normalizes`

Action reduction:
- max 5 actions
- at most 1 action per finding
- if more than 5 findings emit, keep actions for the top 5 retained findings only

Priority assignment:
- sort candidate actions by parent finding severity descending
- then by parent finding confidence descending
- then by fixed actionability order
- assign priorities `1..n`

### Summary construction contract

The producer must derive:
- `status` from emitted findings
- `score` from emitted findings
- `headline` from the top 1-2 most important findings

Headline rules:
- if no findings: `No abnormal system-health signals were identified in the last 60 minutes`
- if one finding: use a one-sentence summary of that finding
- if multiple findings: combine the top two themes with `and`
- max 120 chars
- avoid metric clutter in the headline

Examples:
- `Memory usage is elevated`
- `Disk space is low on C and Print Spooler appears unstable`

### Producer-side validation

Before emission, the producer must validate:
- top-level fields exactness
- enum correctness
- field length caps
- source refs resolve
- related finding IDs resolve
- unique finding IDs
- unique action priorities
- `summary.status` matches finding severities
- `summary.score` matches scoring rule
- `window_minutes == 60`

If validation fails:
- the producer must correct deterministic issues if possible
- otherwise it must fail closed rather than emit invalid JSON
