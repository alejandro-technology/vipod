---
trigger: model_decision
---

# Views & Navigation Rules

Use SwiftUI navigation state to express the player’s menu hierarchy. A screen renders the current destination and forwards user intent; application use cases own library and playback behavior.

## Screen responsibilities

1. Keep menu screens focused on presenting choices and routing to the selected destination.
2. Keep the Now Playing screen focused on current-track presentation and transport controls.
3. Keep file selection UI limited to presenting the system importer and forwarding its result to an import use case.
4. Observe an injected presentation model; do not instantiate a player or repository in a screen.
5. Handle loading, empty-library, unavailable-file, and import-error states explicitly.

## Navigation

- Prefer `NavigationStack` and typed/hashable destinations when supported by the selected target.
- Model the classic iPod menu structure as navigation state rather than a set of unrelated booleans.
- Keep navigation path changes separate from playback lifetime. Popping a screen must not stop audio unless the product explicitly requires it.
- Confirm the target iPod generation and reference flow before naming menus, deciding hierarchy, or reproducing hardware-specific interactions.

## File importer

- Use the system document picker through SwiftUI/UniformTypeIdentifiers for local audio selection where supported.
- Treat picker URLs as security-scoped. Acquire access only while reading/copying, and release it on every success and failure path.
- Copy successful imports to app-owned storage before saving durable library metadata unless a tested bookmark-based design is explicitly selected.
- For multiple selections, preserve successful imports if one item fails and present a useful summary.

## Do not

- Put AVFoundation playback logic in `body` or screen lifecycle hooks.
- Start or stop playback solely because a view appears or disappears.
- Hide import errors or assume a selected external URL remains accessible forever.
