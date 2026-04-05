# PowerClaw Terminal Runner Architecture

Concrete sketch for a terminal-first interactive runner that sits on top of the
current PowerClaw loop, tool registry, and safety model.

This is intentionally not a GUI plan and not a general "agent platform" plan.
The goal is a practical session runner that makes follow-up turns feel natural
without weakening the current product shape.

## Purpose

Today PowerClaw behaves mostly like a single-request command with an internal
loop. A terminal runner would add a real session layer:

- preserve conversational context across follow-up turns
- keep tool usage, failures, and confirmations visible per turn
- let the user refine or continue an investigation without restating everything
- keep transcripts and logs inspectable

The runner should feel like a better shell UX for the current product, not like
a different architecture.

## Product boundaries

In scope for v1:

- one interactive terminal session at a time
- explicit per-turn user input and per-turn final answers
- reuse of the existing approved tool registry
- reuse of the existing confirmation, dry-run, and plan controls
- optional transcript persistence
- explicit session reset and exit

Out of scope for v1:

- GUI or browser chat UI
- background autonomous execution
- multi-session orchestration
- shared server state
- plugin sandbox changes
- streaming partial tokens unless the provider path clearly justifies it later

## Recommended entrypoints

Add a terminal runner entrypoint alongside the current one-shot path:

```powershell
powerclaw chat
powerclaw chat -UseStub
powerclaw chat -Resume .\logs\sessions\session-2026-04-05.jsonl
```

Keep the current one-shot path unchanged:

```powershell
powerclaw "What's eating my CPU?"
```

Possible command shape:

- `powerclaw chat`
- `powerclaw chat -UseStub`
- `powerclaw chat -Plan`
- `powerclaw chat -DryRun`
- `powerclaw chat -SessionName morning-triage`
- `powerclaw chat -Resume <path>`

## High-level architecture

The runner should be a thin orchestration layer over the current loop:

1. terminal runner host
2. session state object
3. existing tool registry and safety model
4. existing provider dispatcher
5. existing loop answer/tool-call behavior
6. transcript/log persistence

Recommended new files:

- `core/Start-PowerClawChat.ps1`
- `core/Read-PowerClawChatInput.ps1`
- `core/Write-PowerClawChatOutput.ps1`
- `core/New-PowerClawSession.ps1`
- `core/Save-PowerClawSession.ps1`

Likely export:

- `Start-PowerClawChat`

Likely alias behavior:

- keep `powerclaw` as-is
- treat `powerclaw chat` as a subcommand in the launcher script

## Session state model

V1 should use an explicit session object rather than teaching the existing loop
to infer history from logs.

Suggested shape:

```powershell
[PSCustomObject]@{
    schema_version = '1'
    kind = 'powerclaw_session'
    id = '2026-04-05T09-30-12-luna'
    created_at = '2026-04-05T09:30:12-05:00'
    updated_at = '2026-04-05T09:42:07-05:00'
    host = 'LUNA'
    mode = 'chat'
    provider = 'claude'
    model = 'claude-sonnet-4-20250514'
    flags = @{
        use_stub = $false
        dry_run = $false
        plan = $false
    }
    turns = @(
        [PSCustomObject]@{
            turn = 1
            user = 'Give me a full system health check'
            assistant = '...'
            tool_events = @(...)
            final_answer = '...'
            created_at = '...'
        }
    )
    pinned_context = @()
}
```

Design constraints:

- session state must be append-friendly and inspectable
- session state must not embed arbitrary raw provider payloads by default
- session state should preserve final answers plus enough tool-event summary to
  understand what happened
- session state should stay portable as JSONL or JSON, not a private binary

## Turn flow

Each interactive turn should do this:

1. read user input
2. intercept slash commands locally if present
3. build the next loop request from the new turn plus bounded prior context
4. run the existing loop
5. print tool activity and final answer
6. append turn data to the session object
7. optionally persist transcript/session state

Important point:

The session runner should not replace `Invoke-ClawLoop`. It should call it with
session-aware inputs and then record the results.

## Context strategy

The runner should not blindly replay the full transcript forever.

Recommended v1 context policy:

- include the current user turn
- include the last `N` turns of user + assistant summaries
- include pinned context entries if the user explicitly pins them
- include the most recent tool-result summaries only when still relevant

Suggested practical default:

- keep the last 4 turns in active context
- summarize older turns into one short session summary string

Why:

- keeps token growth bounded
- avoids stale context overwhelming the current question
- makes the runner feel persistent without becoming sloppy

## Slash commands

V1 should support a small local command set handled before the model runs:

- `/help`
- `/reset`
- `/exit`
- `/save`
- `/plan on`
- `/plan off`
- `/dryrun on`
- `/dryrun off`
- `/tools`
- `/status`
- `/pin <text>`
- `/unpin`

Behavior:

- slash commands do not consume a model turn
- slash commands should print deterministic local output
- `/status` should show current provider, model, flags, session path, and turn count

## Output model

The runner should keep the existing transparency style:

- print each tool request as it happens
- print execution/block/dry-run/confirm states
- print one final answer per turn
- keep write confirmations explicit and interactive

Recommended display additions:

- a visible session header on startup
- per-turn numbering
- clearer separators between turns
- short note when the answer used prior session context

## Safety model

The runner must not weaken existing controls.

Keep unchanged:

- approved tool registry
- disabled tool enforcement
- write confirmation tokens
- evidence-backed delete policy
- dry-run and plan semantics

Runner-specific safety rules:

- session context must not authorize writes by itself
- a previous turn's write confirmation must never carry into a later turn
- pinned context must be treated as reference material, not execution approval
- resumed sessions must preserve auditability of prior turns

## Logging and persistence

The current loop log should remain the event log of record for individual loop
steps. The runner should add a higher-level session transcript on top.

Recommended persistence split:

- existing `loop_log` JSONL stays as-is
- new session transcript stores turn-level summaries

Suggested session path:

- `logs\sessions\session-<timestamp>-<host>.jsonl`

Suggested per-turn transcript record:

```json
{
  "schema_version": "1",
  "kind": "powerclaw_session_turn",
  "session_id": "2026-04-05T09-30-12-luna",
  "turn": 3,
  "timestamp": "2026-04-05T09:38:22-05:00",
  "user": "check that more deeply",
  "assistant": "The repeated Service Control Manager errors still look confined to one service...",
  "tool_events": [
    { "tool": "Get-EventLogEntries", "outcome": "success" }
  ],
  "flags": {
    "plan": false,
    "dry_run": false,
    "use_stub": false
  }
}
```

## Resume behavior

`-Resume` should be explicit.

Recommended behavior:

- load transcript/session metadata from a chosen file
- show a short resume summary before accepting input
- do not silently resurrect old state
- fail clearly if the transcript schema is newer than the current code expects

## Provider and model behavior

The runner should reuse the current provider dispatcher.

Do not create a second provider abstraction just for chat mode.

V1 should:

- use the same `config.json`
- use the same tool schema generation
- use the same final-answer vs tool-call contract

Possible later enhancement:

- optional session-summary compaction when the transcript becomes too long

## Testing strategy

The runner should ship only with offline coverage at first.

Tests to add:

- session startup and shutdown
- slash command handling
- session reset behavior
- transcript persistence
- resume behavior
- confirmation token resets between turns
- bounded active-context construction
- `-UseStub` parity in chat mode

Non-goal for v1 tests:

- no dependence on live provider streaming

## Recommended implementation order

1. Add a session object and transcript persistence helpers.
2. Add `Start-PowerClawChat` with a basic read-eval-print loop.
3. Wire slash commands for `/help`, `/status`, `/reset`, `/save`, `/exit`.
4. Reuse `Invoke-ClawLoop` for each turn without changing the safety model.
5. Add bounded active-context summarization.
6. Add `-Resume`.
7. Only then consider niceties like richer terminal formatting.

## Why this is worth doing

- It turns PowerClaw from a good one-shot command into a more usable assistant.
- It makes follow-up investigation cheaper and more natural.
- It increases the value of the existing tool registry and answer-shaping work.
- It strengthens inspectability because turns, tool events, and outputs become a
  real session artifact instead of isolated command invocations.

## Why this should not be rushed ahead of reliability

The runner multiplies the surface area of whatever answer-shaping and tool
selection behaviors already exist.

That means:

- flaky one-turn behavior becomes flaky multi-turn behavior
- ambiguous summary semantics get carried forward across turns
- bad failure handling becomes more obvious in a chat context

So the right sequencing is:

- keep improving flagship one-turn reliability first
- then add the terminal runner as the next UX layer
