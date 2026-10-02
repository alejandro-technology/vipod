---
trigger: model_decision
---

# Testing Rules

Test observable behavior at the layer that owns it. Discover the existing test targets and framework first; use the project’s Swift Testing or XCTest convention rather than introducing a second framework without reason.

## Test focus

- **Domain:** queue ordering, next/previous boundaries, repeat modes, and shuffle invariants. Inject deterministic randomness where shuffle order is asserted.
- **Application:** play/pause/seek/import orchestration using fakes for repository and audio-engine contracts.
- **Infrastructure:** file-copy and metadata behavior with temporary directories and small local fixtures; validate decoder behavior with a known-good MP3 fixture.
- **Presentation/UI:** menu transitions, accessible control actions, empty/error states, and user-visible playback state.

## Core mandates

1. Assert behavior and state transitions, not private implementation details.
2. Never require real speakers, microphone input, network access, or a user-selected external file for unit tests.
3. Keep AVFoundation behind a protocol so queue and use-case tests are deterministic.
4. Use small redistributable test audio, and document its provenance if one is added.
5. Test interruption, route-change, and background behavior only when those requirements are in scope; keep platform integration tests separate from pure logic tests.
6. Run only commands that exist in the inspected project and report simulator/device limitations accurately.

## Do not

- Assert elapsed-time updates with fragile wall-clock sleeps when a controllable clock or fake engine can be used.
- Make tests depend on audio output hardware.
- Add a coverage threshold or snapshot suite without a project-level reason.
