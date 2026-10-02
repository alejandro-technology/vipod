---
trigger: always_on
---

# Conventions Rules

Use clear, idiomatic Swift and keep product copy localizable. Follow the actual project’s formatter, localization setup, and deployment constraints once they exist.

## Naming and files

- Use `UpperCamelCase` for types and `lowerCamelCase` for properties, methods, and enum cases.
- Use descriptive Swift filenames matching the primary type where practical; avoid abbreviations except established platform terms.
- Keep source identifiers and comments in English unless the repository has an explicit different convention.
- Name protocols by role (`TrackRepository`, `AudioPlayback`) and implementations by technology (`AVFoundationAudioPlayback`).
- Organize source by feature and responsibility; do not encode layer names into every type name.

## Swift and concurrency

- Prefer value types for domain models when identity semantics are not required.
- Make actor isolation explicit for shared mutable state. Use `Sendable` where values cross concurrency boundaries and the compiler/project mode requires it.
- Avoid force unwraps, `try!`, `Task.detached`, and unstructured tasks unless the lifecycle and cancellation behavior are justified.
- Keep UI-facing strings in the project’s localization mechanism. The intended language is not yet specified.

## Imports and APIs

- Import only frameworks used by the file and keep AVFoundation imports inside the infrastructure boundary.
- Use modern SwiftUI APIs only after checking availability for the project target.
- Preserve existing naming, formatting, and test conventions rather than introducing a competing style.
