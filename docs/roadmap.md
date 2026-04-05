# PowerClaw Roadmap

Forward-looking work for the repo. This is not a promise list. It is the current
best ordering of useful next improvements in service of the product vision.

## Product vision

PowerClaw should become the safest and most useful Windows-native command-line
workbench for personal machine operations.

The intended product shape is:
- natural-language control over real Windows tasks
- tool-registry safety instead of arbitrary shell generation
- high trust through inspectability, confirmation, and constrained execution
- fast path from clone to first useful result
- easy extension through drop-in tools

## Product pillars

### 1. Trust and control

The user should understand what PowerClaw can do, what it is about to do, and
what it actually did.

### 2. Windows-native usefulness

The default experience should feel meaningfully better on Windows than generic
terminal agents or shell wrappers.

### 3. Fast setup and first win

A new user should be able to install, configure, and get a useful answer quickly
without hidden machine-specific dependencies.

### 4. Extensible tool ecosystem

Adding or enabling tools should be straightforward without weakening safety.

## Current priorities

### Priority 1: deepen trust and safety policy

- Strengthen destructive-tool safety beyond confirmation tokens and current path
  policy checks where practical.
- Improve real provider-backed answer consistency for flagship workflows,
  especially multi-tool health-check, cleanup, and investigation prompts.
- Decide whether `loop_log` should expand beyond the current v1 event contract
  into a richer execution trace or stay intentionally narrow.
- Keep live provider verification easy to run while preserving the fast offline
  default suite, and keep provider account-state failures diagnosable when a key,
  quota, or billing issue blocks verification.

### Priority 2: keep setup and onboarding sharp

- Keep the README and website aligned around the same onboarding sequence and
  top workflows.
- Preserve Anthropic and OpenAI as equally first-class setup paths.
- Treat `Fetch-WebPage` as part of the first-class workbench surface and make
  its one-time runtime setup explicit in onboarding instead of hiding it behind
  optional positioning.

### Priority 3: strengthen the extensibility story

- Keep expanding contract tests for tool metadata parsing, registration, schema
  generation, and overlay activation behavior.
- Keep overlays lightweight and explicit so machine-specific tools do not drift
  back into the main portable surface.
- Document the drop-in tool authoring path and overlay activation path clearly.

## Recently completed

- Public-facing README and homepage copy now align around the same ICP, the same
  onboarding sequence, and the same top workflows.
- `Invoke-ClawLoop` now gives flagship workflows more explicit answer-shaping
  guidance so health checks, cleanup prompts, and investigation prompts return
  more operator-style summaries.
- `-Plan` now previews a short intended tool chain instead of only the first
  tool request, and stub mode now mirrors that behavior for flagship workflows.
- `-UseStub` now behaves like a believable no-key product demo instead of a
  generic loop smoke path.
- `Invoke-ClawLoop` coverage is materially stronger around unavailable tools,
  repeated tool calls, write confirmations, execution failures, truncation, and
  structured logging behavior.
- Destructive writes now require typed confirmation tokens, and `Remove-Files`
  enforces fully qualified paths plus protected-root blocking.
- Structured logs now distinguish blocked, declined, confirmed, executed, and
  final-answer outcomes explicitly for loop inspection.
- Structured logs now emit versioned `loop_log` v1 JSON lines with stable core
  fields, explicit event/outcome pairs, and a formal schema.
- Install and setup ergonomics improved with provider-specific example configs,
  clearer validation guidance, and better installed-module defaults.
- `Fetch-WebPage` returned to the default workbench surface, and onboarding now
  treats its Playwright setup as a first-class step.
- Personal note-search tools moved into an optional overlay, and the repo now
  includes an overlay install helper for one-machine activation.
- Tool-contract regression coverage now includes metadata parsing, defaults,
  enums, ranges, switch typing, and overlay activation behavior.
- Provider regression coverage now includes offline tool-result roundtrips for
  both Claude and OpenAI, and the live smoke path now verifies final-answer,
  tool-call, and follow-up tool-result flows.
- Claude and OpenAI live smoke are now both verified successfully against the
  real provider paths.
- Deterministic `system_triage` production is now implemented locally, exposed
  through `Invoke-SystemTriage` and `Get-SystemTriage`, and used as the
  preferred first signal for flagship health-check workflows.
- Cleanup prompts now have stronger routing and discovery-budget protection so
  vague “what can I delete” requests are less likely to wander into repeated
  broad searches.
- Read, config, log, and webpage investigation prompts now have an explicit
  synthesis lane with a small default read-only budget so answers stay concise
  and evidence-backed instead of drifting into transcript-style exploration.
- Cleanup answers and delete policy now go further: surfaced candidates get
  explicit review-only versus execution-allowed states, cleanup recommendations
  are ranked more explicitly, and `Remove-Files` blocks permanent or higher-risk
  deletes unless the user is more specific.
- Deterministic `cleanup_summary` production is now implemented locally,
  exposed through `Invoke-CleanupSummary` and `Get-CleanupSummary`, and used as
  the preferred first signal for flagship cleanup workflows.

## Longer-term bets

- Add a richer planning and execution trace if PowerClaw becomes a more active
  workbench instead of a mostly single-request operator.
- Explore deeper Windows-native integrations that strengthen the product moat:
  scheduled tasks, richer service/event workflows, better search and storage diagnostics,
  and other capabilities generic shell agents handle poorly.

## Update rule

Update this file when:
- a planned item becomes active work
- priorities materially change
- an item is completed or intentionally dropped

Remove stale items instead of letting this become an archive.
