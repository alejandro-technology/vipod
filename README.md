# VIPOD

VIPOD is a native SwiftUI music player with an iPod Classic-inspired interface for local music.

## Run

1. Open `vipod.xcodeproj` in Xcode.
2. Select the **vipod** scheme and an iOS 18.6-or-later destination, then run.
3. Choose **Import Music** and select audio files from Files. Browse the library with the on-screen wheel or accessible menu controls; playback continues as you navigate.
4. Open **Settings** to choose the Black or White appearance. `iPodTheme` can be extended with additional palettes.

In **Songs**, highlight a track with the wheel and use the trash button to remove it from VIPOD's library. This does not delete the original audio file from your iPhone.

## Test

Run the `vipod` scheme's tests from Xcode, or use:

```sh
xcodebuild test -project vipod.xcodeproj -scheme vipod -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/vipod-derived
```

The project targets iOS 18.6. Xcode 26.3's available simulator runtime is 26.3; background playback behavior should also be verified on a real device.
