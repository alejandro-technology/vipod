---
name: audio-playback
description: "Trigger: MP3 playback, AVFoundation, audio session, background audio, Now Playing. Implement VIPOD audio behavior and lifecycle."
license: "UNLICENSED"
metadata:
  author: "VIPOD contributors"
  version: "1.0"
---

## Activation Contract

Use for local playback, seeking, queue transitions, interruptions, route changes, or system media controls.

## Hard Rules

- Keep queue policy in Domain/Application and the native player in Infrastructure.
- Reuse one app-scoped engine; never bind engine lifetime to a SwiftUI screen.
- Confirm background/remote-control requirements before adding target capabilities or MediaPlayer integration.
- Verify MP3 behavior with known fixtures on the supported runtime; handle decode and missing-file failures.

## Decision Gates

| Requirement | Investigate |
|---|---|
| Local finite file and standard controls | AVAudioPlayer suitability |
| Streaming, item replacement, or advanced lifecycle | AVPlayer suitability |
| Lock Screen / remote buttons | AVAudioSession plus MediaPlayer integration |

## Execution Steps

1. Read `rules/core-audio.md`, `state-management.md`, and the actual target settings.
2. Define the player protocol and observable state contract.
3. Configure playback session behavior; add background mode only when in scope.
4. Handle completion, interruption, route change, cancellation, and cleanup.
5. Test queue policy with fakes and decoding with a local MP3 fixture.

## Output Contract

State the player API choice, lifecycle behavior, target changes, fixtures, and verification.

## References

- [`../../rules/core-audio.md`](../../rules/core-audio.md)
- [`../../rules/error-handling.md`](../../rules/error-handling.md)
- [`../../rules/testing.md`](../../rules/testing.md)
