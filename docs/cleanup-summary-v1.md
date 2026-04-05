# Cleanup Summary V1

Normative specification for a bounded `cleanup_summary` JSON document intended
for local agent-efficient file cleanup reasoning on Windows.

## Purpose

The producer emits one JSON document summarizing the most relevant cleanup
candidates inside one bounded scope.

The document answers:
- what cleanup candidates were found
- which candidates are review-only versus execution-allowed after confirmation
- what order the user should review them in
- why they are ranked that way
- what the next safe step is

The document does not:
- delete files
- scan arbitrary numbers of directories
- model multiple scopes in one document
- expose raw file listings beyond the bounded candidate set

## Schema scope

The JSON Schema for v1 validates local structure, enums, required fields, and
array caps.

Cross-field invariants such as:
- candidate ID uniqueness
- `recommended_order` resolution
- summary count consistency

remain producer-side validation requirements rather than pure schema guarantees
in v1.

## Allowed collectors

Only these collectors may contribute evidence in v1:
- `Search-Files`

## Top-level document

The document must contain exactly these top-level fields and no others:

```json
{
  "schema_version": "1.0",
  "kind": "cleanup_summary",
  "scope": "C:\\Users\\chris\\Downloads",
  "captured_at": "2026-04-04T18:05:00-05:00",
  "summary": {},
  "candidates": [],
  "recommended_order": [],
  "next_action": {},
  "sources": []
}
```

Rules:
- `schema_version` must equal `1.0`
- `kind` must equal `cleanup_summary`
- `scope` must be a string of 1-260 chars
- `captured_at` must be an ISO 8601 timestamp with offset
- `summary` must be an object
- `candidates` must be an array with at most 10 items
- `recommended_order` must be an array with at most 10 items
- `next_action` must be an object
- `sources` must be an array with at most 4 items

## Summary

`summary` must contain exactly these fields:

```json
{
  "status": "actionable",
  "headline": "Cleanup candidates were found in Downloads, and some low-risk remnants are execution-allowed after confirmation",
  "candidate_count": 4,
  "execution_allowed_count": 1
}
```

Rules:
- `status` must be one of `empty|review_only|actionable`
- `headline` must be a string of 1-160 chars
- `candidate_count` must be an integer from `0` to `10`
- `execution_allowed_count` must be an integer from `0` to `10`

## Candidates

Each candidate must contain exactly these fields:

```json
{
  "id": "candidate:debug_log",
  "name": "debug.log",
  "path": "C:\\Users\\chris\\Downloads\\debug.log",
  "category": "logs",
  "state": "execution_allowed",
  "rank": 1,
  "size_mb": 40.2,
  "modified_at": "2026-04-03T10:15:00-05:00",
  "rationale": "Log, temp, dump, or backup-style remnants are usually the strongest cleanup candidates.",
  "evidence": [
    "Path: C:\\Users\\chris\\Downloads\\debug.log",
    "Size: 40.2 MB"
  ],
  "source_refs": [
    "src_search"
  ]
}
```

Rules:
- `category` must be one of `logs|installer|archive|media|other`
- `state` must be one of `review_only|execution_allowed`
- `rank` must be an integer from `1` to `10`
- `size_mb` must be a non-negative number
- `evidence` must contain 1-3 strings

## Recommended order

`recommended_order` is an ordered list of candidate IDs.

Rules:
- each value must resolve to one candidate in `candidates`
- producer-side validation must ensure no duplicate IDs appear here

## Next action

`next_action` must contain exactly these fields:

```json
{
  "kind": "confirm_delete",
  "reason": "Review the ranked candidates, then confirm only the low-risk remnants the user actually wants removed."
}
```

Rules:
- `kind` must be one of `expand_scope|review_candidates|confirm_delete|none`
- `reason` must be a string of 1-180 chars
