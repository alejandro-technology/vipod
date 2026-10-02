---
trigger: model_decision
---

# Core Audio & File Rules

Treat audio playback and imported-file access as infrastructure behind narrow feature contracts. Playback state is app-scoped; files in the library must remain readable across launches.

## Playback

- Use one AVFoundation-backed engine instance for the active app session.
- Keep queue policy, shuffle, repeat, selection, and user-visible playback state outside the raw player object.
- Configure `AVAudioSession` for playback when audio playback is active product behavior. Background audio also requires the corresponding target capability; enable it only when explicitly in scope.
- If interruptions or route changes are handled, distinguish pause/resume policy from fatal player errors. Resume only when the app was previously playing and the system indicates resumption is appropriate.
- Add Now Playing metadata and remote commands through MediaPlayer only when Lock Screen/Control Center controls are required.
- Verify actual MP3 decoding, duration, seek behavior, and metadata extraction with known fixtures on supported iOS runtimes.

## Imported files

- Treat file-picker URLs as security-scoped external resources. Balance access start/stop on every execution path.
- Prefer copying selected audio into an app-owned library location for durable access; save metadata only after the copy succeeds.
- Use stable track identifiers. Do not use the filename alone as a unique identity.
- Handle duplicates, removed/corrupt files, partial multi-selection success, and insufficient storage as explicit outcomes.
- Do not store AVAudioPlayer/AVPlayer instances or transient external URLs in persistence.

## See also

- [`architecture.md`](architecture.md)
- [`error-handling.md`](error-handling.md)
- [`../skills/audio-playback/SKILL.md`](../skills/audio-playback/SKILL.md)
