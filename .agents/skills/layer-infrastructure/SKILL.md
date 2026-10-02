---
name: layer-infrastructure
description: "Trigger: AVFoundation, file import, audio repository, persistence adapter. Implement native iOS adapters behind VIPOD contracts."
license: "UNLICENSED"
metadata:
  author: "VIPOD contributors"
  version: "1.0"
---

## Activation Contract

Use when implementing storage, file import, media metadata, audio playback, or system-media integration.

## Hard Rules

- Read target settings and confirm API availability before using native APIs.
- Keep AVFoundation and file-system details inside Infrastructure.
- Balance security-scoped access and copy imports to app-owned storage before persisting library entries.
- Map native errors at the adapter boundary; keep cancellation distinct.

## Decision Gates

| Need | Adapter direction |
|---|---|
| Local finite audio | Evaluate AVAudioPlayer against required controls |
| Streaming/item lifecycle or advanced media | Evaluate AVPlayer |
| Remote/Lock Screen controls | Add MediaPlayer only when requested |

## Execution Steps

1. Load `rules/core-audio.md` and `audio-playback` when audio is involved.
2. Implement the existing Domain contract; do not widen it without a concrete use case.
3. Isolate actor/callback handoffs and resource cleanup on every path.
4. Test with temporary files, known local fixtures, and a fake player where possible.

## Output Contract

Report APIs chosen, target compatibility, file/session lifecycle, errors, and verification.

## References

- [`../../rules/core-audio.md`](../../rules/core-audio.md)
- [`../../rules/dependencies.md`](../../rules/dependencies.md)
