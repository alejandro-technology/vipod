---
name: navigation
description: "Trigger: SwiftUI navigation, menu hierarchy, NavigationStack. Model VIPOD destinations and selection flow using project-supported APIs."
license: "UNLICENSED"
metadata:
  author: "VIPOD contributors"
  version: "1.0"
---

## Activation Contract

Use when adding or changing menu destinations, navigation path state, or back/selection behavior.

## Hard Rules

- Inspect target availability and existing navigation conventions before using newer APIs.
- Keep navigation state separate from playback lifetime.
- Confirm the exact iPod model/menu flow before encoding hardware-specific labels or destinations.
- Keep navigation decisions out of reusable rows and wheel drawing code.

## Decision Gates

| Flow | Prefer |
|---|---|
| Typed destinations/path | `NavigationStack` when supported |
| Small fixed menu with custom transitions | Existing project pattern; avoid parallel navigation systems |

## Execution Steps

1. Read `rules/views-navigation.md` and inspect current routes/screens.
2. Define destination identity and back behavior.
3. Connect menu selection to navigation through explicit state/actions.
4. Test open, back, repeated selection, and playback continuity.

## Output Contract

Report destinations, state owner, compatibility checks, and tests.

## References

- [`../../rules/views-navigation.md`](../../rules/views-navigation.md)
- [`../../references/components-gallery/screen-patterns.md`](../../references/components-gallery/screen-patterns.md)
