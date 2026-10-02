---
description: Design or implement a focused SwiftUI screen that follows VIPOD navigation, state, and visual-reference rules.
agent: build
---

Handle the requested screen `$ARGUMENTS` after inspecting the app structure and existing design conventions.

Before pixel-level work, identify the selected iPod generation or approved visual reference. If it is unknown and the request depends on fidelity, ask one focused question. Keep screens compositional: observe injected presentation state, forward named user actions, and leave queue, file, and AVFoundation behavior in their owning layers.

Check loading/empty/error states, NavigationStack behavior, VoiceOver labels/actions, hit targets, and Reduce Motion. Avoid generic system chrome where it conflicts with an approved reference, but do not invent artwork or typography. Run the narrowest available build and UI tests; report paths and results.
