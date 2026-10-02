---
name: layer-domain
description: "Trigger: domain model, track, playback queue, repository contract. Define pure Swift music-player models, invariants, and interfaces."
license: "UNLICENSED"
metadata:
  author: "VIPOD contributors"
  version: "1.0"
---

## Activation Contract

Use before implementing a library or playback capability when its domain types or rules are new or changing.

## Hard Rules

- Keep domain types independent of SwiftUI, AVFoundation, file URLs from the picker, and persistence schemas.
- Model queue and repeat/shuffle behavior as deterministic rules with explicit boundaries.
- Prefer value types and typed identifiers; make concurrency traits explicit when required by the project.

## Decision Gates

| Requirement | Domain output |
|---|---|
| Audio library | Track identity/metadata and repository contract |
| Playback | Queue state, repeat/shuffle policy, playback command contract |
| Import | Result/failure semantics; external URL handling remains infrastructure-owned |

## Execution Steps

1. Read existing types and `rules/architecture.md`.
2. State invariants and failure cases before defining types.
3. Define the smallest model/protocol surface that supports the requested use cases.
4. Add focused tests for invariants and edge cases; avoid framework imports.

## Output Contract

Summarize the domain decisions, contracts, changed files, and tests.

## References

- [`../../rules/architecture.md`](../../rules/architecture.md)
- [`../../rules/error-handling.md`](../../rules/error-handling.md)
