---
name: create-test
description: "Trigger: Swift test, XCTest, Swift Testing, playback test. Add deterministic tests for VIPOD behavior and native adapters."
license: "UNLICENSED"
metadata:
  author: "VIPOD contributors"
  version: "1.0"
---

## Activation Contract

Use when adding, repairing, or reviewing tests for Domain, Application, Infrastructure, or SwiftUI behavior.

## Hard Rules

- Discover the existing test target and use its current framework and deployment/toolchain support.
- Keep domain/application tests independent of audio hardware and wall-clock timing.
- Use fakes for playback contracts and temporary directories for file behavior.
- Use only small, known, appropriately licensed audio fixtures.

## Decision Gates

| Subject | Test strategy |
|---|---|
| Queue/use case | Unit test with deterministic fake and controlled shuffle |
| File import | Temporary folder, cancellation/failure and partial-success cases |
| AVFoundation decode | Focused integration test with local fixture on supported runtime |
| SwiftUI interaction | UI test of accessible actions and visible state |

## Execution Steps

1. Read source and `rules/testing.md`.
2. Identify the observable contract and edge cases.
3. Add the narrowest meaningful test without production-only hooks where possible.
4. Run the exact target and report unavailable simulator/device coverage.

## Output Contract

Report test files, behavior covered, command, and result.

## References

- [`../../rules/testing.md`](../../rules/testing.md)
- [`../../agents/test-writer.md`](../../agents/test-writer.md)
