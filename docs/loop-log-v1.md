# Loop Log V1

Normative specification for append-only `loop_log` JSON entries emitted by
`Invoke-ClawLoop`.

## Purpose

Each log line records one loop event with a stable event/outcome pair and enough
context for lightweight inspection, debugging, and downstream tooling.

The log is:
- append-only
- one JSON object per line
- scoped to one loop event, not a whole session summary

The log is not:
- a full replay transcript
- a stable contract for every preview or payload field forever
- a substitute for reducer document models such as `system_triage` or `cleanup_summary`

## Top-level contract

Every entry must contain exactly these core fields:

```json
{
  "SchemaVersion": "1",
  "Kind": "loop_log",
  "Timestamp": "2026-04-04T20:05:00.0000000-05:00",
  "Event": "tool_result",
  "Outcome": "success",
  "Step": 1
}
```

Rules:
- `SchemaVersion` must equal `1`
- `Kind` must equal `loop_log`
- `Timestamp` must be an ISO 8601 timestamp
- `Event` must be one of the allowed v1 event names
- `Outcome` must be valid for the chosen `Event`
- `Step` must be an integer `>= 1`
- no extra top-level fields are allowed outside the v1 schema

## Reason vocabulary

`loop_log` v1 now uses three different reason lanes on purpose:

- `Reason`
  Event-local explanation for what happened in that specific log event.
- `PolicyReason`
  Normalized write-boundary policy code for delete or other write-gating decisions.
- `ControlReason`
  Normalized loop-control code for preview-only, repeated-call rejection, and latency-budget boundaries.

Use `Reason` for event semantics, and use `PolicyReason` / `ControlReason` when
the repo already has a normalized cross-event vocabulary for the decision.

### `PolicyReason` values

- `explicit_write_intent_required`
- `prior_evidence_required`
- `explicit_permanent_intent_required`
- `specific_user_reference_required`
- `confirmation_declined`
- `execution_mode_dry_run`
- `confirmed_write_execution`

### `ControlReason` values

- `repeated_identical_tool_call`
- `health_check_latency_budget_reached`
- `cleanup_discovery_budget_reached`
- `cleanup_latency_budget_reached`
- `investigation_latency_budget_reached`
- `plan_preview_only`

## Allowed event and outcome pairs

- `step_start` -> `started`
- `model_response` -> `received`
- `plan_preview` -> `previewed`
- `final_answer` -> `final_answer`
- `tool_requested` -> `requested`
- `tool_unavailable` -> `rejected`
- `tool_rejected` -> `rejected`
- `tool_skipped` -> `blocked|declined|dry_run`
- `tool_confirmed` -> `confirmed`
- `tool_result` -> `success|error|executed_success|executed_error`
- `loop_abort` -> `aborted`

## Event-specific fields

### `step_start`

Required:
- `MaxSteps`
- `UserGoal`
- `MessageCount`

### `model_response`

Required:
- `ResponseType`

Optional:
- `ToolName`
- `ToolUseId`

### `plan_preview`

Required:
- `StepCount`

Optional:
- `PlanSummary`
- `Reason`

### `final_answer`

Required:
- `Preview`

### `tool_requested`

Required:
- `Tool`
- `ToolUseId`
- `Args`
- `ToolCallIdentity`

### `tool_unavailable`

Required:
- `Tool`
- `ToolUseId`
- `AvailableTools`

### `tool_rejected`

Required:
- `Tool`
- `ToolUseId`
- `Reason`

### `tool_skipped`

Required:
- `Tool`
- `ToolUseId`
- `Reason`

Optional:
- `PolicyReason`
- `ControlReason`
- `Risk`
- `Args`
- `UserGoal`
- `ToolCount`
- `ConfirmationToken`
- `ConfirmationInput`

When a skipped entry reflects a write-boundary decision, `PolicyReason` should
use one of:
- `explicit_write_intent_required`
- `prior_evidence_required`
- `explicit_permanent_intent_required`
- `specific_user_reference_required`
- `confirmation_declined`
- `execution_mode_dry_run`

When a skipped entry reflects a loop-control or latency-budget decision,
`ControlReason` should use one of:
- `health_check_latency_budget_reached`
- `cleanup_discovery_budget_reached`
- `cleanup_latency_budget_reached`
- `investigation_latency_budget_reached`

### `tool_confirmed`

Required:
- `Tool`
- `ToolUseId`
- `Risk`
- `Args`
- `ConfirmationToken`

### `tool_result`

Required:
- `Tool`
- `ToolUseId`
- `Args`
- `Risk`
- `Status`
- `ResultLen`
- `DryRun`
- `DurationMs`
- `ResultPreview`

Rules:
- `Status` must be `success` or `error`
- `Outcome` distinguishes read-only execution from confirmed write execution
- confirmed write execution may include `PolicyReason = confirmed_write_execution`
- repeated-call or other control-path tool results may include `ControlReason`

### `loop_abort`

Required:
- `Reason`

## Stability guidance

V1 freezes:
- the core fields
- the event names
- the allowed event/outcome pairs
- the required event-specific fields above

V1 does not promise that every optional field will stay present on every event
forever, but if an optional field appears it must still validate against the v1
schema.
