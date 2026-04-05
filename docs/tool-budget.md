# Tool Budget

Default approved tools should stay intentionally small.

## Budget

- Keep the default approved set at `20` tools or fewer.
- Treat `16` to `20` tools as the caution zone.
- Above `20`, require either consolidation, overlays, or a documented reason the default surface must expand.

## Admission rule

A new default tool should clear all of these checks:

1. It answers a real prompt family that the current default tools cannot answer directly.
2. Its core job is clearly distinct from every existing default tool.
3. Its output can be deterministic and structured.
4. A user can describe the need in plain English without naming the tool.
5. The repo can carry routing tests that show when this tool should win over nearby tools.

If one of these fails, the tool should usually not be default-approved.

## Overlap rule

Do not add a default tool when it is mainly:

- a narrower variant of an existing tool
- a second path to answer the same prompt family
- a wrapper around arbitrary shell, registry, or PowerShell access
- a grab-bag of unrelated settings because they are all "system" behavior

If two tools would often compete for the same prompt, that is a sign the surface is drifting.

## Domain rule

Prefer a small set of clear domains:

- health and triage
- cleanup and files
- investigation and evidence
- configuration and state

Within a domain, prefer one synthesized tool over several adjacent raw tools when the user question is naturally one thing.

## Complexity rule

A default tool should usually have:

- one main responsibility
- a small parameter surface
- one stable output shape

If a tool needs many modes, unrelated switches, or mixed responsibilities, it likely wants to be split or moved out of the default set.

## Promotion rule

Promote a tool into the default approved set only when at least one of these is true:

- users repeatedly ask for the capability
- the current toolset repeatedly fails on the same prompt family
- the capability is part of the core product story in README or onboarding
- the tool provides a deterministic answer that is materially better than model-only synthesis

Otherwise prefer keeping it out of the default set.

## Demotion rule

Move a tool to an overlay or optional approval path when it is:

- rarely selected
- heavily overlapping with another tool
- machine-specific
- adding routing confusion
- too broad for the main portable product surface

## Recommended current policy

With the repo currently operating near the middle of the budget, prefer adding at most `2` new default tools before reevaluating the overall surface.

For each proposed tool, answer these questions before approval:

1. What exact prompt family fails today?
2. Why can no current default tool answer it directly?
3. Which nearby tool should this one beat in routing tests?
4. Is it portable enough for the main repo instead of an overlay?
5. Does adding it keep the default set inside the tool budget?
