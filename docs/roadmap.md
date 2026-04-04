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

### Priority 1: sharpen the default product experience

- Tighten the README and website around the current product story:
  Windows-first, provider-configurable, registry-based, safe by default.
- Update public-facing copy that still implies Claude-only behavior where the
  product now supports multiple providers.
- Make the default tool set feel intentional and portable, with optional extras
  clearly separated from the core experience.

### Priority 2: deepen trust and inspectability

- Expand tests around `Invoke-ClawLoop`, especially unavailable-tool handling,
  write confirmations, and multi-step behavior.
- Keep CI enforcing the supported test entrypoint on Windows.
- Improve log clarity and decide whether the log format is part of the supported
  product surface.
- Strengthen safety around destructive tools beyond a single Y/N prompt where
  practical.

### Priority 3: reduce setup friction

- Improve install and upgrade ergonomics for local module deployment.
- Clarify provider setup so Anthropic and OpenAI both feel first-class.
- Reassess whether `Fetch-WebPage` belongs in the core onboarding path or should
  be framed as an optional capability with heavier prerequisites.

### Priority 4: strengthen the extensibility story

- Add stronger contract tests for tool metadata parsing and registration.
- Document the drop-in tool authoring path more clearly.
- Decide whether personal and machine-specific tools should move into optional
  overlays or companion packages.

## Longer-term bets

- Split machine-specific integrations into optional overlays or companion packages.
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
