---
trigger: model_decision
---

# Components Rules

SwiftUI components should be small, composable views with explicit inputs and actions. Shared visual primitives belong in the DesignSystem; feature-specific rendering stays inside its feature.

## Responsibilities

- **Design primitives:** reusable typography, menu rows, artwork frames, and control shapes. They receive values and closures; they do not access repositories or control AVFoundation directly.
- **Feature components:** library rows, album/track details, playback controls, and the click-wheel surface. They map user interaction to named actions.
- **Screens:** compose feature components, observe presentation state, and express navigation. They should not become the place for queue algorithms or file import implementation.

## Interaction and accessibility

- Give each action a clear accessibility label, value, and hint where useful.
- Expose separate accessible actions for wheel regions and transport controls; do not make swipe/rotation gestures the only way to browse or control playback.
- Preserve VoiceOver navigation, adequate hit targets, and Reduce Motion behavior even when matching a retro visual reference.
- Keep artwork, menu text, and status changes distinguishable without color alone.

## Do not

- Build one monolithic `ContentView` for every menu and playback state.
- Put persistence, metadata parsing, or audio-session setup in a view initializer/body.
- Add a reusable component for a one-off layout before a second use case exists.
- Substitute SF Symbols or generic controls for reference-specific artwork without confirming the visual target.

## See also

- [`theme-styles.md`](theme-styles.md)
- [`../references/components-gallery/core-components.md`](../references/components-gallery/core-components.md)
- [`../references/components-gallery/click-wheel.md`](../references/components-gallery/click-wheel.md)
