---
trigger: model_decision
---

# Composition & Lifecycle Rules

Compose long-lived services once at the SwiftUI app boundary. Inject feature-facing contracts into presentation models; keep dependency creation out of view bodies and feature modules.

## Core mandates

1. The app composition root owns one playback engine and the services needed by Library and Playback.
2. Keep construction explicit. Prefer initializer injection for feature models and SwiftUI environment injection for truly app-scoped dependencies.
3. Make production and test compositions differ only in their implementations, not in feature behavior.
4. Keep app/scene lifecycle integration at the outer boundary. Forward lifecycle events to the owning service instead of embedding global observers in screens.
5. Use `@MainActor` for UI-facing observable state when appropriate; isolate lower-level audio/file work according to the actual SDK callback and concurrency contracts.
6. Do not assume an app remains active to finish an import or update playback UI; define cancellation and handoff behavior at the responsible boundary.

## Do not

- Create a new player for each screen or sheet.
- Put business rules in the `App` entry point or a dependency container.
- Use a singleton as a substitute for an explicit composition root.
- Enable background modes, entitlements, or capabilities without a confirmed product requirement.
