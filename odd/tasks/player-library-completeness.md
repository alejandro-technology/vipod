# Complete the player library experience

Deliver four cohesive, reviewable behavior slices that make VIPOD’s library metadata, playback continuity, queue, and collections dependable. Each task includes its behavior, focused tests, and a short README update; do not split implementation into model/service/test-only commits.

## Objective and problem

The player needs reliable album browsing and ordering, continuity across launches, direct queue editing, and user-managed playlists and favorites. Today these behaviors are incomplete or absent, leaving users unable to trust the library’s organization or preserve their listening context.

## Why

These are connected parts of a usable personal music library, but each task should deliver an independently understandable behavior slice with its tests and user-facing documentation. Existing imported audio and stable track identity must remain intact.

## Scope and constraints

- Exactly four work units, in dependency order: T1 metadata; T2 session; T3 queue; T4 playlists and favorites.
- Preserve backwards compatibility with existing `tracks.json`; enrich existing imported songs only best-effort from their app-owned audio. Never invent absent tags, change track IDs, or change audio files.
- Session restoration must wait for library load and restore the exact queue order (including shuffle), selection, elapsed position, repeat, and shuffle state as **paused**. Never autoplay. Handle stale IDs, missing files, and corrupt session data safely. Serialize durable saves and flush progress at reasonable intervals and lifecycle boundaries.
- Queue editing must expose accessible play-next, add-last, move, and remove controls. Queue removal must not delete library tracks.
- Playlists must support named persistent create, rename, delete, add, remove, and reorder; favorites must persist. Provide accessible iPod-style workflows and reconcile collection references after library deletion. Modifying collections must never delete audio.
- Preserve project style, the app-scoped playback engine, resource-free/nonisolated `deinit` behavior, and minimum iOS 18.6/macOS 15.7 support. Do not add unrelated functions beyond these four points.
- Every unit includes behavior, tests, and a short README update. Keep tests/docs with the behavior; do not make separate models/services/tests commits.
- Use strict TDD: observe a behavior-level RED before each behavioral implementation, then GREEN and REFACTOR. A build failure caused only by a missing symbol is not a behavioral RED.
- Baseline: 65 `vipodTests` pass; macOS build passes; no known failing tests.

## Authorized scope

Source edits are authorized only in app/library/playback/navigation composition, tests, README, and this feature document. No source-write permission is granted for `tooling/`, `.atl/`, `.agents/`, assets, or project settings unless necessary and separately approved within the existing scope. Preserve the untracked `.codegraph/` directory.

The active branch is `feat/player-library-completeness`, based on `e1bcd64` (`refactor: separate player menus and library operations`). The existing `feat/vipod-player` work was authorized and fast-forwarded into `main` before this branch. Local commits for this feature and final local merge into `main` are authorized. No push, PR, network, or physical-device operations are authorized. Do not create PRs or simulate a review.

Delivery strategy is `auto-chain`, with `chain_strategy: feature-branch-chain`. Forecast: approximately 700–1000 authored additions plus deletions before implementation. The 400-line/task heuristic is advisory, not a cap: preserve coherent behavior, tests, and docs; never code-golf. Record work-unit slice boundaries and commit identities when known; do not create PRs.

## Acceptance criteria

- [ ] T1 preserves legacy `tracks.json` compatibility, correct album metadata/grouping/order, and best-effort enrichment from already imported app-owned audio without fabricating tags or changing IDs/files.
- [ ] T2 persists and safely restores the complete playback session after library load, paused and without autoplay; durable saves are serialized and progress/lifecycle flushes are reasonable.
- [ ] T3 provides accessible queue play-next, add-last, move, and remove workflows without removing tracks from the library.
- [ ] T4 provides accessible iPod-style persistent named playlist create/rename/delete/add/remove/reorder and persistent favorites; library-deletion reconciliation never deletes audio.
- [ ] Every task delivers implementation, relevant tests, and a short README update as one work unit.
- [ ] Existing baseline behavior remains green; final full test suite, macOS build, and `git diff --check` pass.

## Work units

### T1 — Correct album metadata and ordering

**Route:** delegated to the bounded single writer for this task. Read preparation covered `Track`, `FileTrackRepository`, `ClassicPlayerMenuBuilder`, album navigation, repository/menu tests, and the supported iOS target before corresponding writes; this slice spans 2+ nontrivial source files.

- [ ] Inspect existing metadata persistence, import, browsing, and test paths before implementation.
- [ ] Keep existing `tracks.json` readable and writable compatibly; correctly group and order albums.
- [ ] Best-effort enrich existing imported songs from their app-owned audio without inventing absent tags or changing IDs/files.
- [ ] Add behavior-first tests, short README update, evidence, and one coherent work-unit commit.

### T2 — Restore a durable paused playback session

**Route:** delegated by task boundary after read preparation establishes 2+ nontrivial source files and the relevant load, playback, persistence, and lifecycle call paths. Parent retains native risk, consent, and review.

- [ ] Inspect playback queue/controller, library load flow, app lifecycle, and persistence before implementation.
- [ ] Persist exact queue order (including shuffle), selected item, elapsed position, repeat, and shuffle; restore only after library load and always paused.
- [ ] Handle stale track IDs, missing files, corrupt state, serialized durable saves, progress flushes, and lifecycle flushes.
- [ ] Add behavior-first tests, short README update, evidence, and one coherent work-unit commit.

### T3 — Edit the visible playback queue

**Route:** delegated by task boundary after read preparation establishes 2+ nontrivial source files and queue, navigation/composition, and accessibility call paths. Parent retains native risk, consent, and review.

- [ ] Inspect queue state, navigation/composition, and existing accessible iPod-style interactions before implementation.
- [ ] Deliver accessible play-next, add-last, move, and remove actions for the visible queue; queue removal never deletes a library track.
- [ ] Add behavior-first tests, short README update, evidence, and one coherent work-unit commit.

### T4 — Manage playlists and favorites

**Route:** delegated by task boundary after read preparation establishes 2+ nontrivial source files and collection persistence, library deletion, navigation, and accessibility call paths. Parent retains native risk, consent, and review.

- [ ] Inspect library deletion/reconciliation and existing navigation/accessibility patterns before implementation.
- [ ] Deliver persistent named playlists with create/rename/delete/add/remove/reorder and persistent favorites through accessible iPod-style workflows.
- [ ] Reconcile deleted library tracks from collections without deleting audio when collections are modified.
- [ ] Add behavior-first tests, short README update, evidence, and one coherent work-unit commit.

## Delegation and implementation protocol

Route work by task boundary. Delegation is appropriate for two or more nontrivial files only after read-preparation establishes the relevant code paths and the task’s boundaries. The parent owns native-platform risk, consent, and review; delegated work cannot expand this authorized scope. Apply TDD per behavior: first demonstrate an observed failing behavioral assertion, then implement to GREEN and REFACTOR. Never count missing-symbol compilation failure by itself as RED.

## Verification commands

Focused iOS tests:

```sh
xcodebuild test -project vipod.xcodeproj -scheme vipod -destination 'platform=iOS Simulator,id=BB74B3A7-2E36-4733-A64D-2A67F425F526' -derivedDataPath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-library-work' -only-testing:vipodTests -parallel-testing-enabled NO
```

Final full tests: use the same command without `-only-testing:vipodTests`.

macOS build:

```sh
xcodebuild build -project vipod.xcodeproj -scheme vipod -destination 'platform=macOS' -derivedDataPath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-library-mac-work' CODE_SIGNING_ALLOWED=NO
```

Also run `git diff --check`.

## Progress, evidence, and next step

- **Initial checks:** baseline reported PASS: 65 `vipodTests` and macOS build. Branch and base verified as `feat/player-library-completeness` at `e1bcd64415500e47c3e4f3ea38a2f7b007a23df0`; `.codegraph/` is untracked and must be preserved.
- **T1 progress:** still **PARTIAL**, not complete; parent verification/commit remain pending. Correction pass began with behavior tests before corresponding source correction. RED command: `xcodebuild test -project vipod.xcodeproj -scheme vipod -destination 'platform=iOS Simulator,id=BB74B3A7-2E36-4733-A64D-2A67F425F526' -derivedDataPath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-library-work' -only-testing:vipodTests/FileTrackRepositoryTests -parallel-testing-enabled NO`; before fixes, the tagged existing-audio catalog backfill test failed albumArtist/trackNumber/discNumber/compilation assertions, the write-failure test threw catalogFailure instead of returning readable catalog tracks, and tagged MP3 import exposed an AVFoundation/XCTest error (`NSInvalidUnarchiveOperationException`, surfaced as Cocoa error 4 while cleaning the temporary URL). Additional direct RED: `testLegacyCatalogEnrichmentPersistsTagsWithoutChangingTrackOrAudioIdentity` showed nil album artist/track/disc/compilation. Corrections use typed `AVMetadataIdentifier`s over available non-ID3 asset metadata formats and parse well-formed ID3 text frames (`TPE1`, `TPE2`, `TRCK`, `TPOS`, `TCMP`) without modifying audio bytes. Migration applies cached scan fingerprints only after catalog persistence succeeds; metadata read and catalog write failures preserve the decoded library. Strict historical TDD deviation from the initial pass is retained honestly: initial metadata API and tests predated its first RED. Latest focused repository verification: `xcodebuild test -project vipod.xcodeproj -scheme vipod -destination 'platform=iOS Simulator,id=BB74B3A7-2E36-4733-A64D-2A67F425F526' -derivedDataPath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-library-work' -only-testing:vipodTests/FileTrackRepositoryTests -parallel-testing-enabled NO` **PASS, 8 tests, 0 failures**. Final full unit command above **PASS, 69 tests, 0 failures**; macOS build command above **BUILD SUCCEEDED**; `git diff --check` **PASS**. Known limitation: a purpose-authored tagged MP3 imports through AVFoundation with an unexpected Cocoa/XCTest error in the simulator, so the successful regression directly proves tagged ID3 parsing/backfill from an existing app-owned audio file and persistence after a fresh repository load—not tagged-file import. A deterministic regression for catalog-write failure specifically during migration was not retained; migration now catches write failure and returns decoded tracks, and fingerprint persistence is sequenced after catalog write, but parent should review this branch. Parent must decide whether to add an import/durability test before calling T1 complete. Rollback boundary: revert T1 changes to `Track`, `FileTrackRepository`, `ClassicPlayerMenuBuilder`, `ClassicPlayerMenuTests`, `FileTrackRepositoryTests`, README album note, and T1 evidence only; preserve baseline code and `.codegraph/`. Commit identity pending; no PR slice exists.
- **T2–T4:** not started; record behavior-level RED, GREEN/refactor, focused test result, README change, commit identity, and rollback/slice boundary for each completed unit.
- **Chain record:** `auto-chain` / `feature-branch-chain`; no commits or PR slices exist yet.
- **Next step:** parent reviews source and the tagged-import/durability limitations, decides whether to request follow-up evidence, then records verification and makes the T1 commit. Do not dispatch T2 until parent accepts T1. No T2–T4 implementation is included.

## Source allowance

Implementation may touch only app/library/playback/navigation composition, tests, and README, plus this document. Tooling, `.atl/`, `.agents/`, assets, and project settings remain outside source-write scope unless necessary and separately approved.
