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
- Decide whether the structured log contract should expand beyond the current
  minimal supported subset.
- Keep live provider verification easy to run while preserving the fast offline
  default suite.

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
- Structured logs now include a minimal supported subset with `SchemaVersion`
  and stable core fields for every entry.
- Install and setup ergonomics improved with provider-specific example configs,
  clearer validation guidance, and better installed-module defaults.
- `Fetch-WebPage` returned to the default workbench surface, and onboarding now
  treats its Playwright setup as a first-class step.
- Personal note-search tools moved into an optional overlay, and the repo now
  includes an overlay install helper for one-machine activation.
- Tool-contract regression coverage now includes metadata parsing, defaults,
  enums, ranges, switch typing, and overlay activation behavior.

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
