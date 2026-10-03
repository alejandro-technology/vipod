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

- [x] T1 preserves legacy `tracks.json` compatibility, correct album metadata/grouping/order, and best-effort enrichment from already imported app-owned audio without fabricating tags or changing IDs/files (implementation and focused test/commit evidence recorded below; RDD is OFF/disabled/unmanaged by explicit clone choice).
- [x] T2 persists and safely restores the complete playback session after library load, paused and without autoplay; durable saves are serialized and progress/lifecycle flushes are reasonable.
- [x] T3 provides accessible queue play-next, add-last, move, and remove workflows without removing tracks from the library.
- [ ] T4 provides accessible iPod-style persistent named playlist create/rename/delete/add/remove/reorder and persistent favorites; library-deletion reconciliation never deletes audio.
- [ ] Every task delivers implementation, relevant tests, and a short README update as one work unit.
- [ ] Existing baseline behavior remains green; final full test suite, macOS build, and `git diff --check` pass.

## Work units

### T1 — Correct album metadata and ordering

**Route:** delegated to the bounded single writer for this task. Read preparation covered `Track`, `FileTrackRepository`, `ClassicPlayerMenuBuilder`, album navigation, repository/menu tests, and the supported iOS target before corresponding writes; this slice spans 2+ nontrivial source files.

- [x] Inspect existing metadata persistence, import, browsing, and test paths before implementation.
- [x] Keep existing `tracks.json` readable and writable compatibly; correctly group and order albums.
- [x] Best-effort enrich existing imported songs from their app-owned audio without inventing absent tags or changing IDs/files.
- [x] Add behavior-first tests, short README update, evidence, and one coherent work-unit commit. The initial pass preceded its first behavior-level RED; that historical TDD sequence deviation remains explicit below.

### T2 — Restore a durable paused playback session

**Route:** delegated by task boundary after read preparation establishes 2+ nontrivial source files and the relevant load, playback, persistence, and lifecycle call paths. Parent retains native risk, consent, and review.

- [x] Inspect playback queue/controller, library load flow, app lifecycle, and persistence before implementation.
- [x] Persist exact queue order (including shuffle), selected item, elapsed position, repeat, and shuffle; restore only after library load and always paused.
- [x] Handle stale track IDs, missing files, corrupt state, serialized durable saves, progress flushes, and lifecycle flushes.
- [x] Add behavior-first tests and short README update. Parent completion confirmed at commit `c18092c` (`feat(playback): restore durable paused sessions`); focused Session + LibraryOperations verification passed 18 tests, with 80 unit tests and macOS build reported passing.

### T3 — Edit the visible playback queue

**Route:** delegated by task boundary after read preparation establishes 2+ nontrivial source files and queue, navigation/composition, and accessibility call paths. Parent retains native risk, consent, and review.

- [x] Inspect queue state, navigation/composition, and existing accessible iPod-style interactions before implementation.
- [x] Deliver accessible play-next, add-last, move, and remove actions for the visible queue; queue removal never deletes a library track.
- [x] Add behavior-first tests, short README update, evidence, and one coherent work-unit commit. Parent verification/commit remains pending.

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
- **T1 implementation and commit:** commit `a151be3` (`feat(library): preserve album metadata and track order`), 7 paths, 481 additions / 19 deletions including tracking. Full writer units: **69 passed, 0 failed**; macOS build **PASS**; `git diff --check` **PASS**. Independent Luna-fast exact selection `FileTrackRepositoryTests` + `ClassicPlayerMenuTests`: **16 passed, 0 failed**, using derived data `vipod-library-independent-t1`; parent reran `git diff --check` **PASS**. No confirmed defect found. No native review/receipt is complete.
- **T1 historical TDD and test limitations:** the initial-pass behavior implementation/tests predated its first behavior-level RED; this sequence deviation remains explicit. Tagged-import and migration-save-failure tests were removed as unstable/not retained. The passing removal catalog-write test is **not** evidence of migration-save-failure behavior. Do not claim migration write-failure proof or successful tagged-file import.
- **T1 native review status:** user explicitly disabled native RDD for this clone; RDD is OFF/disabled/unmanaged by human choice. No native review/approval/receipt is claimed or expected under this choice. Preserve `.codegraph/` and eligible `.gitignore`.
- **Native review policy:** user explicitly chose to disable RDD for this clone; do not ask about changing this policy again. Preserve `.codegraph/` and `.gitignore`.
- **T2 initial TDD deviation:** the first attempt added behavior before a behavior-level RED; this is a historical deviation and is not represented as satisfying TDD. A corrective bounded RED step then compiled and executed five `PlaybackSessionPersistenceTests`, observing 12 assertion failures (0 unexpected): exact restore state and stale/duplicate pruning assertions failed, as did file-adapter round-trip equality. The first run had test-compilation errors and a temp-folder setup error; these were corrected before the observed behavioral RED. During final parallel verification, one simulator test invocation exited with signal 9 before bootstrapping while the focused and full test commands targeted the same simulator concurrently; an immediate rerun of both commands passed (focused 8/8, full 77/77). No assertion/test was removed.
- **T2 GREEN:** focused command `xcodebuild test -project vipod.xcodeproj -scheme vipod -destination 'platform=iOS Simulator,id=BB74B3A7-2E36-4733-A64D-2A67F425F526' -derivedDataPath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-library-work' -only-testing:vipodTests/PlaybackSessionPersistenceTests -parallel-testing-enabled NO` **PASS, 8 tests, 0 failures**. It covers deterministic fake stores/engine, controlled delayed-load completion, atomic adapter round-trip/deletion and corrupt data, paused exact restore, stale/duplicate pruning, mutation saves, and user-action-wins. Full command using the same runner with `-only-testing:vipodTests` **PASS, 77 tests, 0 failures**. Exact macOS build command in Verification commands **BUILD SUCCEEDED**; `git diff --check` **PASS**. Earlier GREEN attempts exposed adapter-revision-zero and pre-restore-intent issues; both were fixed before final focused/full evidence. Runtime evidence is XCTest + supported macOS build; no physical-device run was authorized. Abrupt termination may lose changes since last periodic progress checkpoint (5-second interval). Parent completion is recorded below.
- **T2 rollback boundary:** revert the T2-specific changes in `PlaybackSession.swift`, `PlaybackQueue.swift`, `PlaybackController.swift`, `FilePlaybackSessionStore.swift`, `AppDependencies.swift`, `ClassicPlayerLibraryOperations.swift`, `ClassicPlayerView.swift`, `PlaybackSessionPersistenceTests.swift`, and the playback paragraph in `README.md`; preserve all T1 source, the user's existing task-document edits, and `.codegraph/`.
- **T2 corrective batch RED:** added three behavioral regressions before production edits. Focused `PlaybackSessionPersistenceTests` RED: `testFlushBeforeAndDuringRestorePreservesPreviouslySavedSession` (2 assertion failures) and `testUserActionDuringLoadIsSavedAboveLoadedRevision` (2 assertion failures); `ClassicPlayerLibraryOperationsTests` RED: `testFailedInitialLibraryLoadDoesNotConsumePausedSessionRestore` (2 assertion failures). Both commands compiled and ran; total 6 assertion failures, 0 unexpected. Regressions use delayed store continuations and revision-aware retained state; no sleeps.
- **T2 corrective batch GREEN:** focused session suite **10 passed, 0 failed** and library-operations suite **8 passed, 0 failed**. Startup restore now waits for a successful library load; session flushes/autosaves are suppressed until restore resolves; loaded revision seeds even when user intent wins, then current user state is saved at a higher revision. Full unit suite **80 passed, 0 failed**; macOS build **BUILD SUCCEEDED**; `git diff --check` **PASS**. Two intervening simulator invocations failed to launch the app with `FBSOpenApplicationServiceErrorDomain Code=1`, reason `Busy` during CoreSimulator preflight; focused reruns and the final serialized full suite passed. Parent completion and commit are recorded below.
- **T2 parent completion:** branch HEAD `c18092c05a0a7caafd4668f5b11a7a314eb53f93`, commit `feat(playback): restore durable paused sessions`, 11 paths, 520 additions / 22 deletions. Parent reports the exact focused Session + LibraryOperations command passed **18 tests, 0 failures**, with result bundle `Test-vipod-2026.10.03_11-15-08--0500.xcresult`; full writer unit/macOS evidence remains as recorded above. T2 is complete.
- **T3 behavior and tests:** queue-domain `enqueueNext`, `addLast`, and visible-index `move` preserve unique IDs/current selection and maintain shuffle order; controller edits persist through the existing T2 session mechanism without touching the audio engine. Main menu has stable `menu.queue`; track lists expose distinct Play Next/Add to Queue actions; the queue screen exposes selection, Play, disabled move-boundary controls, move, and queue-only removal. A deterministic DEBUG-only launch fixture writes 32-second WAV tracks/catalog/session only under the constant `VIPOD-UITesting` Application Support root; reset is honored only with `--uitesting-reset-library`, while relaunch reuses fixture files. Release builds and ordinary launches retain the standard storage root.
- **T3 strict-TDD RED evidence:** the initial `PlaybackQueueEditingTests` command compiled and ran 4 tests with **6 assertion failures, 0 unexpected** in `/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-t3-red.xcresult`: `testPlayNextAndAddLastRepositionUniqueTracksWithoutReloadingCurrentPlayback` (3 order assertions), `testExplicitMovePreservesCurrentTrackAndInvalidBoundariesAreNoOps` (2 order assertions), and `testMainMenuContainsStableQueueEntry` (1 assertion). Continuity/load-count and background/current removal assertions passed. After adding the separate user-intent behavior that selecting a queued track plays it without queue replacement, `testSelectingQueuedTrackPlaysItWithoutReplacingTheQueue` compiled and produced a behavior RED with **3 assertion failures** in `/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-t3-queue-play-red.xcresult`; the model's queue Select action was inert. No missing-symbol compile failure was counted as RED and no test was removed.
- **T3 final verification:** focused `PlaybackQueueEditingTests`: **9 passed, 0 failed**, result `/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-t3-focused-queueview.xcresult`. Full `vipodTests`: **89 passed, 0 failed**, result `/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-t3-unit-queueview.xcresult`. Targeted native UI test `ClassicPlayerUITests/testQueueActionsReorderWithoutPlaybackOrLibraryRemovalAndPersistOnRelaunch`: **1 passed, 0 failed**, result `/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-t3-ui-queueview.xcresult`; it operates the fixture's three WAV songs, adds next/last, asserts the visible queue order, moves and removes queue items, confirms the same selected/current track remains paused, relaunches to verify persistence, and confirms the removed-from-queue song remains in Songs. macOS build `xcodebuild build -quiet -project vipod.xcodeproj -scheme vipod -destination 'platform=macOS' -derivedDataPath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-library-mac-work' CODE_SIGNING_ALLOWED=NO` **PASS**; `git diff --check` **PASS**. Tests ran serially on the authorized simulator. An initial UI runner invocation hit simulator `Busy` before execution; after checking simulator state and retrying sequentially, actual UI runs exposed accessibility query/selection-value issues, which were fixed and the final test passed. One initial full-unit run also caught the expected root-menu selected-index adjustment (old last index 4, now 5); expectation updated, no test removed. Parent independent verification/commit remains pending.
- **T3 exact final test commands:**

  ```sh
  xcodebuild test -quiet -project vipod.xcodeproj -scheme vipod -destination 'platform=iOS Simulator,id=BB74B3A7-2E36-4733-A64D-2A67F425F526' -derivedDataPath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-library-work' -resultBundlePath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-t3-focused-queueview.xcresult' -only-testing:vipodTests/PlaybackQueueEditingTests -parallel-testing-enabled NO
  xcodebuild test -quiet -project vipod.xcodeproj -scheme vipod -destination 'platform=iOS Simulator,id=BB74B3A7-2E36-4733-A64D-2A67F425F526' -derivedDataPath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-library-work' -resultBundlePath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-t3-unit-queueview.xcresult' -only-testing:vipodTests -parallel-testing-enabled NO
  xcodebuild test -quiet -project vipod.xcodeproj -scheme vipod -destination 'platform=iOS Simulator,id=BB74B3A7-2E36-4733-A64D-2A67F425F526' -derivedDataPath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-library-work' -resultBundlePath '/var/folders/_8/xr5shfw97998zq57_jc38zlh0000gn/T/opencode/vipod-t3-ui-queueview.xcresult' -only-testing:vipodUITests/ClassicPlayerUITests/testQueueActionsReorderWithoutPlaybackOrLibraryRemovalAndPersistOnRelaunch -parallel-testing-enabled NO
  ```
- **Chain record:** `auto-chain` / `feature-branch-chain`; no PR/push requested.
- **Next step:** parent performs independent verification and handles the authorized local commit/integration workflow. No stage/commit/merge was performed in this T3 implementation step. T4 remains untouched.

## Source allowance

Implementation may touch only app/library/playback/navigation composition, tests, and README, plus this document. Tooling, `.atl/`, `.agents/`, assets, and project settings remain outside source-write scope unless necessary and separately approved.
