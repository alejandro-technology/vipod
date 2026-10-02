---
name: layer-ui
description: "Trigger: SwiftUI screen, player controls, library UI. Build VIPOD presentation from injected state and explicit actions."
license: "UNLICENSED"
metadata:
  author: "VIPOD contributors"
  version: "1.0"
---

## Activation Contract

Use for library, menu, import, and Now Playing views or their presentation models.

## Hard Rules

- Observe injected state; do not construct players, repositories, or persistence in a view.
- Keep queue/file/audio logic outside `body` and view lifecycle callbacks.
- Confirm the iPod reference before asserting visual fidelity.
- Provide accessible alternatives to custom wheel gestures.

## Decision Gates

| Change | Read first |
|---|---|
| Menu or screen | `views-navigation.md` and screen patterns |
| Wheel/controls | `components.md`, click-wheel pattern, `audio-playback` |
| Visual tokens | `theme` skill and approved reference |

## Execution Steps

1. Inspect the existing SwiftUI state and navigation pattern.
2. Define the screen’s input state and named user actions.
3. Compose small feature views and explicit loading/empty/error states.
4. Verify accessibility actions, navigation, and available build/UI tests.

## Output Contract

Report changed views, state/action contracts, accessibility checks, and test/build results.

## References

- [`../../rules/components.md`](../../rules/components.md)
- [`../../rules/views-navigation.md`](../../rules/views-navigation.md)
- [`../../references/components-gallery/screen-patterns.md`](../../references/components-gallery/screen-patterns.md)
