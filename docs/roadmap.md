# PowerClaw Roadmap

Forward-looking work for the repo. This is not a promise list. It is the current
best ordering of useful next improvements in service of the product vision.

## Product vision

PowerClaw should become the safest and most useful Windows-native machine
assistant for personal machine operations.

The intended product shape is:
- natural-language control over real Windows tasks
- tool-registry safety instead of arbitrary shell generation
- high trust through inspectability, confirmation, and constrained execution
- fast path from clone to first useful result
- easy extension through drop-in tools

Internally, the repo can still evolve as a PowerShell workbench. Externally, the
product story should stay centered on operator outcomes rather than on the
architecture itself.

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
- Keep live provider verification easy to run while preserving the fast offline
  default suite, and keep provider account-state failures diagnosable when a key,
  quota, or billing issue blocks verification.

### Priority 2: deepen object-model leverage

PowerClaw should get more value from the PowerShell object model before it adds
many more surface-area tools. The highest-leverage path is to standardize how
approved tools return, filter, correlate, rank, and reduce structured objects
so more user questions can be answered locally and deterministically.

Scope:
- Prefer object-first tool outputs and reducers over preformatted text so the
  loop can sort, filter, group, compare, and truncate data predictably.
- Treat bounded reducer documents as layered summaries built from object-first
  tools, not as a reason to erase access to direct raw evidence when the user
  clearly needs the underlying objects or a narrower follow-up read.
- Standardize a small shared query vocabulary where it fits the underlying data,
  such as `Scope`, `Limit`, `SortBy`, temporal bounds, and threshold-style
  filters.
- Add more deterministic bounded reducers built from existing tool outputs
  instead of answering every repeated operator question with a new bespoke tool.
- Lean into cross-tool correlation where stable keys already exist, such as PID,
  service name, path, source, and timestamp.
- Keep the schemas strict and the reducers bounded so object leverage improves
  trust and repeatability instead of widening the execution model.

Non-goals:
- Do not turn PowerClaw into a generic query engine over arbitrary host data.
- Do not add broad abstraction layers that make simple tools harder to author or
  reason about.
- Do not replace useful direct tools with opaque reducers when the user clearly
  needs the raw underlying objects.
- Do not optimize for theoretical composability at the cost of simple offline
  tests and inspectable behavior.

Candidate leverage points:
- Add reducer-style workflows for repeated operator questions such as recent
  changes, failed-service summaries, event-source summaries, and download or
  storage hygiene.
- Add lightweight snapshot-and-diff flows where object identity is stable enough
  to compare before-versus-after states safely.
- Improve local ranking and pre-aggregation so the model sees smaller,
  higher-signal evidence sets instead of raw long lists.
- Standardize evidence objects versus summary documents so answers stay concise
  without losing inspectability.

Why this matters:
- It turns PowerShell's object model into a real product advantage instead of a
  hidden implementation detail.
- It lets PowerClaw answer more useful questions with fewer tools and less model
  improvisation.
- It strengthens determinism, testing, and safety across multiple workflows at
  once.

### Priority 3: make time-bounded object queries first-class

PowerClaw already exposes timestamps, relative windows, and structured objects
in several places. The next useful step is not a generic temporal query engine.
It is a small, consistent time-filter surface that lets the user ask questions
like "what changed in the last 24 hours?" and get object-shaped results from
approved tools.

Scope:
- Standardize read-only temporal parameters where they fit the underlying data:
  `HoursBack` for recent-event style queries, and `After` / `Before` for
  timestamped file or record queries.
- Prefer object-preserving filters over text shaping so tools continue to return
  sortable, composable PowerShell objects instead of preformatted summaries.
- Add deterministic reducers where the time window itself is the product value,
  such as recent file churn, recent system changes, and bounded event summaries.
- Keep schemas strict and explicit so models can only request supported temporal
  arguments and cannot invent ad hoc date fields.
- Preserve offline regression coverage for temporal translation, default windows,
  inclusive boundary behavior, and empty-result handling.

Non-goals:
- Do not add a general-purpose time-series database or analytics engine.
- Do not introduce background collection, scheduled sampling, or persistent
  historical retention by default.
- Do not let temporal support become a loophole for arbitrary query generation
  outside the approved tool contract.
- Do not force every tool to support time filters when the underlying source
  does not expose a meaningful timestamp.

Candidate tools and surfaces:
- Extend `Search-Files` with explicit `After` / `Before` filtering on
  `System.DateModified`, so file questions can be answered as real object
  queries instead of sort-only approximations.
- Extend `Get-DirectoryListing` with optional `After` / `Before` filters on
  `LastWriteTime` for bounded local directory inspection.
- Keep `Get-EventLogEntries` as the pattern for relative-window event queries,
  and consider adding `StartTime` / `EndTime` only if the schema remains simple.
- Add a deterministic reducer for "recent changes" style prompts, likely as a
  bounded document built from existing file and event surfaces rather than a
  broad new execution loop.
- Consider temporal views inside `Get-SystemTriage` or a sibling reducer for
  "what changed recently" prompts, but only if the output remains evidence-
  backed and bounded.

Why this matters:
- It leans into PowerShell's object-oriented strengths instead of flattening
  everything into strings.
- It improves common operator questions without weakening the constrained tool
  model.
- It creates a clearer Windows-native moat around event, filesystem, and local
  diagnostic workflows.

### Priority 4: keep setup and onboarding sharp

- Keep the README and website aligned around the same onboarding sequence and
  top workflows.
- Preserve Anthropic and OpenAI as equally first-class setup paths.
- Make demo-mode onboarding explicit so a no-key first win is part of the
  supported product story.
- Keep native local workflows as the default path to first value.
- Make heavier web-investigation runtime setup explicit and optional instead of
  part of the minimum onboarding path.

### Priority 5: deepen the Windows-operator moat

- Strengthen event-log, service, recent-change, and failure-correlation flows so
  PowerClaw feels meaningfully better on Windows than generic terminal agents.
- Improve cleanup intelligence around Windows-specific junk patterns, remnants,
  and low-risk versus review-only distinctions.
- Keep local knowledge search as a supporting evidence lane for operator
  questions, not as the primary product identity.

### Priority 6: strengthen the extensibility story

- Keep expanding contract tests for tool metadata parsing, registration, schema
  generation, and overlay activation behavior.
- Keep overlays lightweight and explicit so machine-specific tools do not drift
  back into the main portable surface.
- Document the drop-in tool authoring path and overlay activation path clearly.
- Make configurable local knowledge search a near-term core extension path by
  shipping a generic tool that defaults to Documents and can be expanded with
  additional directories from `config.json`.

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
- `Fetch-WebPage` remains a supported repo capability, while the default product
  direction is shifting toward native-local-first onboarding with web runtime
  setup positioned as an explicit optional extension.
- `Search-LocalKnowledge` is now part of the default approved surface, using
  `config.json` directories and a Documents default to bring generic local
  context search into the portable core.
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

- Add a terminal-first interactive runner on top of the current loop once the
  flagship one-turn workflows are more consistently reliable. The intended shape
  is a narrow `powerclaw chat` session layer with transcript persistence,
  bounded active context, slash commands, and unchanged tool-registry safety.
  See [terminal-runner-architecture.md](terminal-runner-architecture.md).
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
