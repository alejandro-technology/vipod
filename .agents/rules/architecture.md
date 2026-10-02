---
trigger: always_on
---

# Architecture Rules

Use feature-oriented Clean Architecture. The Domain describes music-player concepts and rules; Application coordinates use cases; Infrastructure adapts Apple APIs and storage; Presentation renders the experience in SwiftUI. The app composition root connects the layers.

## Dependency rules

1. Presentation depends on Application and read-only Domain models; it never constructs AVFoundation players or accesses imported files directly.
2. Application depends on Domain contracts, not concrete AVFoundation or file-system implementations.
3. Infrastructure implements Domain contracts and may import Apple frameworks. Domain never imports SwiftUI, AVFoundation, or UI-specific types.
4. The app composition root is the only place that knows concrete implementations and assembles the dependency graph.
5. Keep cross-feature APIs small. Share technical capabilities, not feature-specific business rules.

## Proposed organization

```text
App/                         # SwiftUI entry point and dependency composition
Core/DesignSystem/           # Shared visual tokens and reusable primitives
Features/
  Library/{Domain,Infrastructure,Application,Presentation}/
  Playback/{Domain,Infrastructure,Application,Presentation}/
Navigation/                  # Menu destinations and navigation state
Resources/                   # Localized strings, approved artwork, audio fixtures
Tests/                       # Targets and suites discovered from the Xcode project
```

Treat this as a logical layout, not a mandate to create Swift packages or Xcode targets. Match the project’s actual organization once it exists.

## Feature responsibilities

- **Library Domain:** track identity and metadata, library rules, and repository contracts.
- **Library Infrastructure:** import/copy selected audio into app-owned storage and read metadata using suitable Apple APIs.
- **Playback Domain/Application:** queue rules, current selection, repeat/shuffle behavior, and play/pause/seek/next/previous use cases.
- **Playback Infrastructure:** one AVFoundation-backed playback adapter and any explicitly required system-media adapters.
- **Presentation:** menu screens, now-playing content, and controls that express user intent through application APIs.

## Do not

- Put queue rules, shuffle logic, or file-management decisions in SwiftUI views.
- Store a security-scoped external URL as if it were permanently accessible. Import the file into app-owned storage or explicitly design and test bookmark-based access.
- Let multiple screens create competing player instances or duplicate authoritative playback state.
- Create a generic framework, package, or abstraction without a concrete second use case.
- Assume a sample directory tree is already present; inspect the repository before using paths in a change.

## Reference

The component and screen patterns are summarized in [`../references/components-gallery/screen-patterns.md`](../references/components-gallery/screen-patterns.md).
