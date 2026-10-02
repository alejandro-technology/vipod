---
trigger: always_on
---

# Rules — Index

Start here for the project’s architectural and development constraints. Detailed rules own decisions; skills describe execution workflows.

1. **Architecture** — feature-oriented Clean Architecture with inward dependencies. See [`architecture.md`](architecture.md).
2. **Error handling** — typed errors at boundaries, user-safe messages, and no silent failures. See [`error-handling.md`](error-handling.md).
3. **State management** — one owner for playback state; separate durable library data from transient UI state. See [`state-management.md`](state-management.md).
4. **Components** — reusable SwiftUI views stay presentational and narrowly scoped. See [`components.md`](components.md).
5. **Views & navigation** — model menu navigation as state and keep screens focused on composition. See [`views-navigation.md`](views-navigation.md).
6. **Dependencies** — prefer native Apple APIs and verify availability against the actual target. See [`dependencies.md`](dependencies.md).
7. **Theme & styles** — derive visual tokens from the approved iPod reference; do not invent fidelity details. See [`theme-styles.md`](theme-styles.md).
8. **Testing** — test domain behavior deterministically and isolate AVFoundation behind test doubles. See [`testing.md`](testing.md).
9. **Composition & lifecycle** — create shared services at the app boundary and inject them. See [`providers.md`](providers.md).
10. **Core audio** — centralize playback-session, file, and system-media integration. See [`core-audio.md`](core-audio.md).
11. **Conventions** — consistent Swift naming, localization, concurrency, and file organization. See [`conventions.md`](conventions.md).

## Product baseline

The intended first use case is importing local audio files and operating a music library with iPod-style browsing and playback controls. Requirements for the exact iPod model, background audio, remote controls, localization, and supported iOS version are not yet specified. Ask before making those choices part of implementation.
