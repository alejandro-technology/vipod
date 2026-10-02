---
description: Add or review local audio import and library persistence for supported iOS files.
agent: build
---

Implement local audio import only when requested. Inspect the app’s deployment target, storage conventions, test setup, and allowed file types first. Load `layer-infrastructure`, `layer-application`, `layer-ui`, `audio-playback`, and `create-test` as applicable.

Treat picker results as security-scoped URLs. Balance access acquisition and release on all paths, copy each successful file into app-owned storage before persisting its track record, and handle cancellation, duplicates, unavailable files, insufficient storage, and partial multi-selection success. Verify MP3 decoding and metadata behavior with a known-good fixture on the supported runtime; do not trust extensions alone.

Do not retain external URLs as permanent file references or add a package without a documented need. Report supported types, storage behavior, tests, and any compatibility limits.
