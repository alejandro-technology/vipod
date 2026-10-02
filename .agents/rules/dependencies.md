---
trigger: model_decision
---

# Dependencies Rules

Prefer the Apple SDK for a native iOS player. Do not add a package until a real requirement cannot be met cleanly with the selected SDK and deployment target.

## Preferred native capabilities

| Need | First choice | Boundary |
|---|---|---|
| Interface and navigation | SwiftUI | Presentation |
| Local audio playback and media metadata | AVFoundation | Playback/Library Infrastructure |
| File type identification and document import | UniformTypeIdentifiers + SwiftUI importer | Library Presentation/Infrastructure |
| Lock Screen, Control Center, remote commands | MediaPlayer, only if required | Playback Infrastructure |
| Local persistence | Existing project choice; otherwise choose after storage needs are known | Infrastructure |

## Core mandates

1. Inspect the Xcode project, deployment target, and current package declarations before selecting APIs or adding a dependency.
2. Verify availability and behavior for the actual iOS versions and devices that the product will support.
3. Confirm MP3 fixtures decode on the supported runtime; do not infer codec or metadata behavior from a filename extension alone.
4. Prefer the smallest native abstraction that supports required controls. Choose AVAudioPlayer or AVPlayer based on needed playback, streaming, and item lifecycle behavior rather than habit.
5. If a package is proposed, document the concrete gap it fills, maintenance status, platform support, and why an Apple API is insufficient.

## Do not

- Add a networking stack, database, or audio framework for speculative future requirements.
- Import one infrastructure framework throughout the UI when a narrow adapter can contain it.
- Enable background audio or remote media integrations as an incidental side effect; treat them as product and target-configuration decisions.
- Assume a dependency is compatible with the project’s Swift concurrency or deployment settings without checking.
