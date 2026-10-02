# VIPOD — Agent Guide

VIPOD is planned as a native iOS music player with an iPod-inspired interface and local audio-library playback, especially MP3 files. Use Swift and SwiftUI for the app and Apple frameworks before considering third-party packages.

## Project status

The repository was empty when this guide was created. The files in this directory describe the intended architecture; they are not evidence that an Xcode project, deployment target, package manager, or test target already exists. Inspect the repository before implementation and do not invent project settings.

## Architectural direction

- Organize features around `Library` and `Playback`, with `Domain`, `Infrastructure`, `Application`, and `Presentation` responsibilities.
- Keep dependencies pointing inward: Presentation → Application → Domain; Infrastructure implements Domain contracts. The app composition root wires concrete implementations.
- Keep Domain independent of SwiftUI and AVFoundation. Isolate native audio, file access, and system media integration behind infrastructure boundaries.
- Use one app-scoped playback engine. Views render state and send user intent; they do not create or own audio players.
- Prefer SwiftUI, AVFoundation, UniformTypeIdentifiers, and other Apple SDK APIs. Add a package only for a demonstrated need.

## Product decisions still open

- Which iPod generation/model is the visual reference? Do not claim pixel fidelity or invent exact dimensions, typefaces, artwork, or controls before a reference is supplied.
- Is background playback, Lock Screen/Control Center metadata, and remote-control support required?
- What iOS deployment target and Xcode/Swift versions should be supported?
- Which UI language and localization scope should be used?

When one of these decisions blocks the requested work, ask one focused question before encoding an assumption.

## Canonical rules

Start with [`rules/index.md`](rules/index.md), then read the detailed rules for the affected area. Skills provide task workflows; rules define constraints. Existing project configuration, once created, is authoritative for supported SDK APIs and test commands.

## Project skills

- [`module-scaffold`](skills/module-scaffold/SKILL.md) — create a feature module.
- [`layer-domain`](skills/layer-domain/SKILL.md) — define models, invariants, and contracts.
- [`layer-infrastructure`](skills/layer-infrastructure/SKILL.md) — implement file and AVFoundation adapters.
- [`layer-application`](skills/layer-application/SKILL.md) — implement use cases and orchestration.
- [`layer-ui`](skills/layer-ui/SKILL.md) — build SwiftUI presentation.
- [`navigation`](skills/navigation/SKILL.md) — model the menu and navigation flow.
- [`audio-playback`](skills/audio-playback/SKILL.md) — implement playback and iOS audio lifecycle behavior.
- [`create-test`](skills/create-test/SKILL.md) — add focused tests.
- [`theme`](skills/theme/SKILL.md) — implement the approved iPod-inspired visual system.

## Change discipline

Inspect relevant project files before planning or editing. Keep changes within the requested scope, preserve existing user work, avoid speculative dependencies, and report which checks were run. Do not create app source files when the request is limited to `.agents`.
