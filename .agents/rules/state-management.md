---
trigger: always_on
---

# State Management Rules

State ownership follows lifetime and responsibility. The playback engine is app-scoped; an observable presentation model projects its state to SwiftUI; the library repository owns durable track records and app-owned audio files.

## Ownership

| State | Owner | Persistence |
|---|---|---|
| Track records and imported-file references | Library repository | Persist according to the project’s selected store |
| Current engine status and elapsed playback time | Single playback service | Runtime; do not persist live engine objects |
| Queue, selected track, repeat/shuffle choices | Playback application model | Persist only if product requirements call for session restoration |
| Selected menu, sheet, alert, transient gesture state | SwiftUI presentation | In memory |

## Core mandates

1. Maintain one authoritative playback state. Views observe it; they do not copy it into separate local state.
2. Keep derived values (formatted time, progress fraction, selected menu label) derived rather than independently mutable.
3. Create one playback service at the app composition boundary and inject the same instance into screens that need it.
4. Use `@Observable` with SwiftUI `@State`/`Environment` when supported by the actual deployment target and project toolchain; otherwise follow the project’s existing observation pattern.
5. Isolate UI-facing mutable state to `@MainActor`. Handle callbacks from audio infrastructure with explicit actor-safe handoff; do not assume callbacks arrive on the main actor.
6. Persist stable track identifiers and queue intent, not AVFoundation objects, temporary URLs, timers, or view state.

## Do not

- Make a SwiftUI view’s lifetime control whether audio continues playing.
- Keep duplicate current-track, is-playing, or progress flags in unrelated views.
- Persist playback state before deciding whether relaunch should restore a queue or resume position.
- Use a global service locator when constructor or environment injection is clear.
