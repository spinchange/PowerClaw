# System Triage V1 Fixtures

Canonical examples and conformance scenarios for `system_triage` v1.

## Purpose

These fixtures exist to:
- make the spec concrete
- expose ambiguity before implementation
- support producer tests
- provide sample expected outputs for documentation

## Canonical healthy fixture

Expected behavior:
- no findings
- no actions
- `summary.status = ok`
- `summary.score = 0`

```json
{
  "schema_version": "1.0",
  "kind": "system_triage",
  "host": "ws-01",
  "captured_at": "2026-04-04T18:05:00-05:00",
  "window_minutes": 60,
  "summary": {
    "status": "ok",
    "score": 0,
    "headline": "No abnormal system-health signals were identified in the last 60 minutes"
  },
  "findings": [],
  "actions": [],
  "sources": [
    {
      "id": "src_system",
      "tool": "Get-SystemSummary",
      "captured_at": "2026-04-04T18:04:20-05:00",
      "scope": "local_host"
    },
    {
      "id": "src_processes",
      "tool": "Get-TopProcesses",
      "captured_at": "2026-04-04T18:04:25-05:00",
      "scope": "top_processes"
    },
    {
      "id": "src_services",
      "tool": "Get-ServiceStatus",
      "captured_at": "2026-04-04T18:04:31-05:00",
      "scope": "important_services"
    },
    {
      "id": "src_events",
      "tool": "Get-EventLogEntries",
      "captured_at": "2026-04-04T18:04:40-05:00",
      "scope": "last_60_minutes"
    },
    {
      "id": "src_storage",
      "tool": "Get-StorageStatus",
      "captured_at": "2026-04-04T18:04:45-05:00",
      "scope": "fixed_volumes"
    }
  ]
}
```

## Canonical warning fixture

Expected behavior:
- one `high_memory` warning
- one action
- score `20`

```json
{
  "schema_version": "1.0",
  "kind": "system_triage",
  "host": "ws-01",
  "captured_at": "2026-04-04T18:05:00-05:00",
  "window_minutes": 60,
  "summary": {
    "status": "warning",
    "score": 20,
    "headline": "Memory usage is elevated"
  },
  "findings": [
    {
      "id": "high_memory:global",
      "type": "high_memory",
      "severity": "warning",
      "category": "memory",
      "title": "Memory usage is elevated",
      "reason": "Memory usage crossed the warning threshold during the observation window",
      "evidence": [
        "Memory in use: 87%",
        "Top memory process: Code at 842 MB"
      ],
      "confidence": 0.95,
      "source_refs": [
        "src_system",
        "src_processes"
      ]
    }
  ],
  "actions": [
    {
      "id": "inspect_memory_top_processes",
      "priority": 1,
      "kind": "inspect",
      "target": "processes",
      "reason_code": "memory_consumers_review",
      "reason": "Review the top memory consumers to identify avoidable pressure",
      "related_finding_ids": [
        "high_memory:global"
      ]
    }
  ],
  "sources": [
    {
      "id": "src_system",
      "tool": "Get-SystemSummary",
      "captured_at": "2026-04-04T18:04:20-05:00",
      "scope": "local_host"
    },
    {
      "id": "src_processes",
      "tool": "Get-TopProcesses",
      "captured_at": "2026-04-04T18:04:25-05:00",
      "scope": "top_processes"
    }
  ]
}
```

## Canonical mixed fixture

Expected behavior:
- two warnings
- score `40`
- headline combines the top two findings

```json
{
  "schema_version": "1.0",
  "kind": "system_triage",
  "host": "ws-01",
  "captured_at": "2026-04-04T18:05:00-05:00",
  "window_minutes": 60,
  "summary": {
    "status": "warning",
    "score": 40,
    "headline": "Memory usage is elevated and Print Spooler appears unstable"
  },
  "findings": [
    {
      "id": "high_memory:global",
      "type": "high_memory",
      "severity": "warning",
      "category": "memory",
      "title": "Memory usage is elevated",
      "reason": "Memory usage crossed the warning threshold during the observation window",
      "evidence": [
        "Memory in use: 87%",
        "Top memory process: Code at 842 MB"
      ],
      "confidence": 0.95,
      "source_refs": [
        "src_system",
        "src_processes"
      ]
    },
    {
      "id": "unstable_service:spooler",
      "type": "unstable_service",
      "severity": "warning",
      "category": "service",
      "title": "Spooler appears unstable",
      "reason": "The service showed a recent instability signal during the observation window",
      "evidence": [
        "Service state: running",
        "Recent failure signals: 1",
        "Recent service-related event activity was observed"
      ],
      "confidence": 0.9,
      "source_refs": [
        "src_services",
        "src_events"
      ]
    }
  ],
  "actions": [
    {
      "id": "inspect_memory_top_processes",
      "priority": 1,
      "kind": "inspect",
      "target": "processes",
      "reason_code": "memory_consumers_review",
      "reason": "Review the top memory consumers to identify avoidable pressure",
      "related_finding_ids": [
        "high_memory:global"
      ]
    },
    {
      "id": "confirm_spooler_stability",
      "priority": 2,
      "kind": "confirm",
      "target": "service:Spooler",
      "reason_code": "service_instability_confirmation",
      "reason": "Confirm whether the service instability is ongoing or user-impacting",
      "related_finding_ids": [
        "unstable_service:spooler"
      ]
    }
  ],
  "sources": [
    {
      "id": "src_system",
      "tool": "Get-SystemSummary",
      "captured_at": "2026-04-04T18:04:20-05:00",
      "scope": "local_host"
    },
    {
      "id": "src_processes",
      "tool": "Get-TopProcesses",
      "captured_at": "2026-04-04T18:04:25-05:00",
      "scope": "top_processes"
    },
    {
      "id": "src_services",
      "tool": "Get-ServiceStatus",
      "captured_at": "2026-04-04T18:04:31-05:00",
      "scope": "important_services"
    },
    {
      "id": "src_events",
      "tool": "Get-EventLogEntries",
      "captured_at": "2026-04-04T18:04:40-05:00",
      "scope": "last_60_minutes"
    }
  ]
}
```

## Conformance scenarios

### 1. Healthy machine

Inputs:
- CPU below 70%
- memory below 80%
- no monitored volume below 20% free
- no unstable allowlisted services
- no dominant event source at or above 5 warnings or errors

Expected:
- no findings
- no actions
- status `ok`
- score `0`

### 2. High memory only

Inputs:
- memory `>= 80%` and `< 92%`
- all other conditions normal

Expected:
- one finding: `high_memory:global`
- severity `warning`
- one action: `inspect_memory_top_processes`
- status `warning`
- score `20`

### 3. Critical low disk

Inputs:
- one fixed monitored volume with free space `<= 10%`
- all other conditions normal

Expected:
- one finding: `low_disk:<volume>`
- severity `critical`
- one action targeting the affected volume
- status `critical`
- score `40`

### 4. One unstable service

Inputs:
- one allowlisted service has one recent failure signal
- no other finding thresholds crossed

Expected:
- one finding: `unstable_service:<service>`
- severity `warning`
- one `confirm` action
- status `warning`
- score `20`

### 5. Multiple unstable services

Inputs:
- two or more allowlisted services qualify as unstable

Expected:
- one rolled-up finding: `unstable_service:multiple`
- severity `critical`
- one `escalate` action
- status `critical`
- score `40`

### 6. Dominant event-log source

Inputs:
- one source has `>= 5` warnings or errors in 60 minutes
- fewer than 10 error-level events

Expected:
- one finding: `repeated_system_errors:<source>`
- severity `warning`
- one inspect action targeting that source
- status `warning`
- score `20`

### 7. Recent reboot plus another finding

Inputs:
- uptime `< 2 hours`
- at least one other emitted finding exists

Expected:
- `abnormal_uptime_signal:global` also emits
- severity `info`
- total score unchanged by the uptime finding
- status derived from the highest non-info finding

### 8. Long uptime plus another finding

Inputs:
- uptime `> 720 hours`
- at least one other emitted finding exists

Expected:
- `abnormal_uptime_signal:global` emits as `warning`
- score increases by `20`

## Negative cases

These documents must be rejected by producer-side validation:
- unknown top-level fields
- `window_minutes` not equal to `60`
- duplicate finding IDs
- duplicate action priorities
- `source_refs` that do not resolve
- `related_finding_ids` that do not resolve
- `summary.status` inconsistent with findings
- `score` inconsistent with scoring rules
- more than one `low_disk` finding
- more than one `repeated_system_errors` finding
