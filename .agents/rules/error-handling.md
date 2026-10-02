---
trigger: always_on
---

# Error Handling Rules

Keep native failures at infrastructure boundaries and expose actionable, typed failures to application and presentation layers. Swift’s `throws`/`async throws` is the default propagation mechanism; use `Result` only when a value-based contract materially helps.

## Core mandates

1. Translate AVFoundation, file-coordination, permission, and persistence failures at the boundary where their meaning is known.
2. Preserve the underlying error for diagnostics without showing raw system messages to users.
3. Keep cancellation distinct from playback or import failure; do not turn `CancellationError` into a generic alert.
4. Present a concise localized message and a recoverable action when possible (retry, reselect file, or remove unavailable track).
5. Report failures that affect observable behavior. Never silently swallow import, playback, or persistence errors.
6. Avoid `try!`, force-unwrapped imported metadata, and broad `catch` blocks that discard context.

## Boundary flow

```text
SwiftUI action → Application use case → Domain contract
                                  ↓
                         Infrastructure adapter
                                  ↓
               typed app failure / successful value
                                  ↓
             localized presentation and diagnostics
```

## Audio and file edge cases

- A file can disappear, become unreadable, or fail decoding after appearing in the library. Surface a recoverable unavailable-track state.
- Import cancellation is not an error. Partial multi-file imports should report which items succeeded and failed without losing successful imports.
- Playback interruptions and route changes are lifecycle events, not automatically fatal errors.
- Do not expose filesystem paths, permission internals, or raw `NSError` descriptions as user-facing copy.

## Do not

- Branch on localized error text.
- Convert every native error to one untyped generic error before logging its context.
- Resume playback after a system interruption without checking the prior playback state and the system’s resume signal.
