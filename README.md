# VIPOD

VIPOD is a native SwiftUI music player with an iPod Classic-inspired interface for local music.

## Run

1. Open `vipod.xcodeproj` in Xcode.
2. Select the **vipod** scheme and an iOS 18.6-or-later destination, then run.
3. Choose **Import Music** and select audio files from Files. Browse the library with the on-screen wheel or accessible menu controls; playback continues as you navigate.
4. Open **Settings** to choose the Black or White appearance. `iPodTheme` can be extended with additional palettes.

Use the wheel to highlight a row and press the center to open or play it. Touching collection songs only selects them; contextual actions are in the panel below the LCD. In **Songs**, the panel's delete action removes a song from VIPOD's library without deleting the original audio file.

Playback restores the last selected track, queue order, shuffle order, repeat setting, and position after the library loads, always paused. Session progress is checkpointed periodically and flushed at playback changes and when the app scene becomes inactive or enters the background. An abrupt operating-system termination may lose progress since the last checkpoint.

Open **Queue** from the main menu to view upcoming tracks. Select a queue item and use the panel below the screen to move it or remove it from playback; the wheel center plays the selected item. Removing from the queue never removes the song from the library. Queue edits are saved with the playback session.

Open **Music → Playlists** to create a playlist (including when the list is empty), or select one to rename or delete it from the panel. Open a playlist to play tracks in saved order; use **Add Songs** to browse the library with the wheel, then press the center to add a selected track. Playlist member actions can reorder or remove that member. **Music → Favorites** lists favorited songs; select one to toggle its favorite state or access additional song actions from the panel. These collection changes never delete library audio. Playlists and favorites survive relaunch, and an unreadable collection catalog is preserved until a successful retry.

## Test

Album browsing groups tracks by album artist when tagged, groups tagged compilations under “Various Artists,” and orders known disc and track numbers first. Each track retains its credited artist; older `tracks.json` catalogs remain readable and missing metadata is enriched best-effort from app-owned audio.

Run the `vipod` scheme's tests from Xcode, or use:

```sh
xcodebuild test -project vipod.xcodeproj -scheme vipod -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .derivedData
```

The project targets iOS 18.6. Xcode 26.3's available simulator runtime is 26.3; background playback behavior should also be verified on a real device.
