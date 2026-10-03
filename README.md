# VIPOD

VIPOD is a native SwiftUI music player with an iPod Classic-inspired interface for local music.

## Run

1. Open `vipod.xcodeproj` in Xcode.
2. Select the **vipod** scheme and an iOS 18.6-or-later destination, then run.
3. Choose **Import Music** and select audio files from Files. Browse the library with the on-screen wheel or accessible menu controls; playback continues as you navigate.
4. Open **Settings** to choose the Black or White appearance. `iPodTheme` can be extended with additional palettes.

In **Songs**, highlight a track with the wheel and use the trash button to remove it from VIPOD's library. This does not delete the original audio file from your iPhone.

Playback restores the last selected track, queue order, shuffle order, repeat setting, and position after the library loads, always paused. Session progress is checkpointed periodically and flushed at playback changes and when the app scene becomes inactive or enters the background. An abrupt operating-system termination may lose progress since the last checkpoint.

Open **Queue** from the main menu to view upcoming tracks. In a song list, open a track's actions menu to play it next or add it to the end of the queue. Select a queue item to move it up or down or remove it from playback; removing from the queue never removes the song from the library. Queue edits are saved with the playback session.

## Test

Album browsing groups tracks by album artist when tagged, groups tagged compilations under “Various Artists,” and orders known disc and track numbers first. Each track retains its credited artist; older `tracks.json` catalogs remain readable and missing metadata is enriched best-effort from app-owned audio.

Run the `vipod` scheme's tests from Xcode, or use:

```sh
xcodebuild test -project vipod.xcodeproj -scheme vipod -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/vipod-derived
```

The project targets iOS 18.6. Xcode 26.3's available simulator runtime is 26.3; background playback behavior should also be verified on a real device.
