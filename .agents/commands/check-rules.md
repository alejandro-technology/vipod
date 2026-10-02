---
description: Audit VIPOD changes against the project’s Swift architecture and iOS audio rules without editing files.
agent: build
---

Review the current working-tree changes and relevant surrounding code against [`../rules/index.md`](../rules/index.md). Check architecture direction, single playback ownership, imported-file lifetime, audio lifecycle, Swift concurrency, iPod-reference fidelity, accessibility, and focused tests.

Do not modify files. Cite changed paths and line numbers, separate confirmed defects from open product decisions, and return findings by severity plus checks already run. If the repository has no source or project files, report that clearly instead of inventing violations.
