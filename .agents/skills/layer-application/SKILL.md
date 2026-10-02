---
name: layer-application
description: "Trigger: playback use case, import workflow, queue orchestration. Implement VIPOD application behavior over domain contracts."
license: "UNLICENSED"
metadata:
  author: "VIPOD contributors"
  version: "1.0"
---

## Activation Contract

Use when coordinating import, library operations, queue policy, or playback commands without rendering UI or directly calling Apple frameworks.

## Hard Rules

- Depend on Domain contracts, not AVFoundation or SwiftUI.
- Keep one app-scoped playback owner and publish a coherent state transition.
- Make cancellation, partial imports, unavailable tracks, and command failures observable.

## Decision Gates

| Work | Application responsibility |
|---|---|
| Import | Coordinate repository import and return per-file outcomes |
| Transport | Apply queue rules, then issue engine commands |
| Presentation state | Map domain/service state into a view-facing model at the presentation boundary |

## Execution Steps

1. Read the domain contracts and `rules/state-management.md`.
2. Define use-case inputs, outputs, cancellation behavior, and state ownership.
3. Orchestrate repositories and audio contracts without knowing concrete adapters.
4. Test with deterministic fakes; verify state and queue behavior.

## Output Contract

List use cases, state ownership, failure behavior, files changed, and checks.

## References

- [`../../rules/state-management.md`](../../rules/state-management.md)
- [`../../rules/error-handling.md`](../../rules/error-handling.md)
