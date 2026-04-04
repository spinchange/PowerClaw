# PowerClaw Project Notes

This file is the repo-wide continuity note for keeping durable docs current as
work happens across actions, slices, and turns.

## Purpose

Use this file as the update protocol for repo knowledge hygiene.
It is not a changelog and not a scratchpad.

## Source-of-truth split

- `AGENTS.md`
  Contributor and agent workflow guidance for working in this repo.
- `docs/decisions.md`
  Durable architectural and policy decisions.
- `docs/roadmap.md`
  Forward-looking prioritized work.
- `docs/known-issues.md`
  Real unresolved limitations and accepted rough edges.
- `README.md`
  User-facing setup and usage guidance.

## Product alignment rule

When updating roadmap or durable notes, anchor them to the product vision first:

- Windows-native usefulness
- trust through constrained execution and inspectability
- fast onboarding to first useful result
- safe extensibility through approved tools

Do not let the roadmap become only a list of engineering chores. Engineering work
should be framed in terms of which product pillar it strengthens.

## Update protocol

When a work slice or session changes the repo, check whether any of the following
must also be updated before the work is considered done:

1. `README.md`
   Update when user-facing setup, usage, install, or testing changed.
2. `AGENTS.md`
   Update when contributor workflow or repo operating rules changed.
3. `docs/decisions.md`
   Update when a new durable tradeoff or policy was chosen.
4. `docs/roadmap.md`
   Update when priorities changed or a planned item was completed or dropped.
5. `docs/known-issues.md`
   Update when a limitation becomes worth tracking or stops being true.

## Maintenance rule

Do not let durable repo knowledge live only in chat history.
If a decision, issue, or standing priority will matter in a later turn, capture it
in the appropriate file during the same slice of work.

## Practical standard

Small code-only changes do not require touching these docs every time.
But if a later contributor would benefit from knowing the change without reading
git history or prior chat context, the relevant durable doc should be updated.
