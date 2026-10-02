#if os(iOS) && canImport(MediaPlayer)
import AVFoundation
import MediaPlayer
import XCTest
@testable import vipod

@MainActor
final class MediaPlayerNowPlayingAdapterTests: XCTestCase {
    func testPausedSingleTrackPublishesMetadataAndSeekProgressThenUnbinds() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-TestTone", withExtension: "mp3"))
        let track = Track(
            title: "VIPOD Test Tone",
            artist: "VIPOD Test Suite",
            album: "Synthetic Fixtures",
            audioFilename: fixture.lastPathComponent
        )
        let engine = AVFoundationAudioPlayback(mediaURLResolver: { _ in fixture })
        let controller = PlaybackController(engine: engine, tracks: [track])
        let adapter = MediaPlayerNowPlayingAdapter(artworkURLResolver: { _ in nil })
        defer {
            adapter.unbind()
            engine.stop()
        }

        controller.next()
        XCTAssertEqual(controller.currentTrack?.id, track.id)
        XCTAssertEqual(engine.status, .paused)

        adapter.bind(controller: controller, engine: engine)
        let center = MPNowPlayingInfoCenter.default()
        let initialInfo = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(initialInfo[MPMediaItemPropertyTitle] as? String, track.title)
        XCTAssertEqual(initialInfo[MPMediaItemPropertyArtist] as? String, track.artist)
        XCTAssertEqual(initialInfo[MPMediaItemPropertyAlbumTitle] as? String, track.album)
        XCTAssertEqual(initialInfo[MPMediaItemPropertyPlaybackDuration] as? Double ?? 0, 1, accuracy: 0.15)
        XCTAssertEqual(initialInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        XCTAssertEqual(initialInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 0)
        let commands = MPRemoteCommandCenter.shared()
        XCTAssertTrue(commands.playCommand.isEnabled)
        XCTAssertTrue(commands.pauseCommand.isEnabled)
        XCTAssertTrue(commands.togglePlayPauseCommand.isEnabled)
        XCTAssertTrue(commands.changePlaybackPositionCommand.isEnabled)
        XCTAssertTrue(commands.previousTrackCommand.isEnabled)

        controller.seek(to: 0.4)
        let updatedInfo = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(updatedInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? 0, 0.4, accuracy: 0.02)

        adapter.unbind()
        XCTAssertNil(center.nowPlayingInfo)
        XCTAssertFalse(commands.playCommand.isEnabled)
        XCTAssertFalse(commands.pauseCommand.isEnabled)
        XCTAssertFalse(commands.togglePlayPauseCommand.isEnabled)
        XCTAssertFalse(commands.nextTrackCommand.isEnabled)
        XCTAssertFalse(commands.previousTrackCommand.isEnabled)
        XCTAssertFalse(commands.changePlaybackPositionCommand.isEnabled)
        XCTAssertNil(engine.onNowPlayingChange)
    }

    func testRemovingCurrentTrackClearsNowPlayingInfoAndDisablesRemoteCommands() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-TestTone", withExtension: "mp3"))
        let tracks = [
            Track(title: "VIPOD Test Tone", artist: "VIPOD Test Suite", album: "Synthetic Fixtures", audioFilename: fixture.lastPathComponent),
            Track(title: "Remaining Track", artist: "VIPOD Test Suite", album: "Synthetic Fixtures", audioFilename: fixture.lastPathComponent),
        ]
        let engine = AVFoundationAudioPlayback(mediaURLResolver: { _ in fixture })
        let controller = PlaybackController(engine: engine, tracks: tracks)
        let adapter = MediaPlayerNowPlayingAdapter(artworkURLResolver: { _ in nil })
        defer {
            adapter.unbind()
            engine.stop()
        }

        controller.next()
        XCTAssertEqual(controller.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(engine.status, .paused)

        adapter.bind(controller: controller, engine: engine)
        let center = MPNowPlayingInfoCenter.default()
        XCTAssertNotNil(center.nowPlayingInfo)
        let commands = MPRemoteCommandCenter.shared()

        controller.removeTrack(id: tracks[0].id)

        XCTAssertNil(controller.currentTrack)
        XCTAssertEqual(controller.status, .idle)
        XCTAssertEqual(controller.elapsed, 0)
        XCTAssertEqual(controller.duration, 0)
        XCTAssertEqual(controller.queue.tracks.map(\.id), [tracks[1].id])
        XCTAssertNil(center.nowPlayingInfo)
        XCTAssertFalse(commands.playCommand.isEnabled)
        XCTAssertFalse(commands.pauseCommand.isEnabled)
        XCTAssertFalse(commands.togglePlayPauseCommand.isEnabled)
        XCTAssertFalse(commands.nextTrackCommand.isEnabled)
        XCTAssertFalse(commands.previousTrackCommand.isEnabled)
        XCTAssertFalse(commands.changePlaybackPositionCommand.isEnabled)
    }
}
#endif
