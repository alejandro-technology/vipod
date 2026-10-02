---
description: Plan and implement a VIPOD feature module using the approved Swift Clean Architecture boundaries.
agent: build
---

Create the requested feature named `$ARGUMENTS` only after inspecting the repository and confirming the user asked for implementation.

Canonical guidance: [`../rules/index.md`](../rules/index.md). Load `module-scaffold` and the relevant layer skills before editing. Keep Domain independent of SwiftUI/AVFoundation, define contracts before adapters, and follow the existing Xcode organization rather than assuming folders or Swift packages.

For a non-trivial feature, plan its behavior, boundaries, open product choices, files, and verification first. Add only the layers the feature needs. Register new resources, navigation destinations, test targets, or target capabilities only when they are required and supported by the existing project.

Report created/changed paths, contracts, checks run, and any unresolved decision.
