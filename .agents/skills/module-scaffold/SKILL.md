---
name: module-scaffold
description: "Trigger: new feature, module scaffold, feature architecture. Plan and scaffold one VIPOD feature within the existing Swift project structure."
license: "UNLICENSED"
metadata:
  author: "VIPOD contributors"
  version: "1.0"
---

## Activation Contract

Use when the user requests a new feature boundary such as Library or Playback. Do not scaffold source for a planning-only request.

## Hard Rules

- Inspect Xcode groups/targets and existing folders before choosing paths.
- Keep Domain free of SwiftUI and AVFoundation; wire implementations at the app composition root.
- Do not add a package or Xcode target unless the requirement justifies it.

## Decision Gates

| Need | Include |
|---|---|
| Business rules/models | Domain + Application |
| Persistence or Apple API | Infrastructure implementing a contract |
| User interaction | Presentation; navigation only if destinations change |

## Execution Steps

1. Load `rules/architecture.md` and the layer skills for the requested behavior.
2. Name responsibilities, contracts, state owner, failures, and tests before creating files.
3. Add only necessary layers and register dependencies in the app composition root.
4. Verify the project’s actual build/test targets.

## Output Contract

Report paths, contracts, layers included, checks, and remaining product decisions.

## References

- [`../../rules/architecture.md`](../../rules/architecture.md)
- [`../layer-domain/SKILL.md`](../layer-domain/SKILL.md)
