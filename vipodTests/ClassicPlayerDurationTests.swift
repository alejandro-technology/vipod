import XCTest
@testable import vipod

@MainActor
final class ClassicPlayerDurationTests: XCTestCase {
    func testUsesPositiveFinitePlaybackDurationBeforeTrackDuration() {
        let track = Track(title: "Song", duration: 90, audioFilename: "song.mp3")
        let model = makeModel(track: track, playbackDuration: 125)

        XCTAssertEqual(model.currentTrackDurationText, "2:05")
    }

    func testFallsBackToValidTrackDurationWhenPlaybackDurationIsUnavailable() {
        let track = Track(title: "Song", duration: 90, audioFilename: "song.mp3")
        let model = makeModel(track: track, playbackDuration: .nan)

        XCTAssertEqual(model.currentTrackDurationText, "1:30")
    }

    func testUnknownDurationUsesPlaceholder() {
        let track = Track(title: "Song", audioFilename: "song.mp3")
        let model = makeModel(track: track, playbackDuration: .infinity)

        XCTAssertEqual(model.currentTrackDurationText, "--:--")
    }

    func testFormattedTimeHandlesNonFiniteAndUnrepresentableValuesSafely() {
        let model = makeModel(track: nil, playbackDuration: 0)

        XCTAssertEqual(model.formattedTime(.nan), "--:--")
        XCTAssertEqual(model.formattedTime(.infinity), "--:--")
        XCTAssertEqual(model.formattedTime(Double.greatestFiniteMagnitude), "--:--")
    }

    func testFormattedTimeSupportsDurationsBeyondThirtyTwoBitIntegerRange() {
        let model = makeModel(track: nil, playbackDuration: 0)

        XCTAssertEqual(model.formattedTime(2_147_483_648), "35791394:08")
    }

    private func makeModel(track: Track?, playbackDuration: TimeInterval) -> ClassicPlayerModel {
        let library = LibraryController(repository: DurationTestRepository())
        let engine = DurationTestPlayback(duration: playbackDuration)
        let playback = PlaybackController(engine: engine, tracks: track.map { [$0] } ?? [])
        if let track { playback.play(track) }
        return ClassicPlayerModel(library: library, playback: playback)
    }
}

private actor DurationTestRepository: TrackRepository {
    func tracks() async throws -> [Track] { [] }
    func importTracks(from urls: [URL]) async throws -> TrackImportReport { await TrackImportReport(imported: []) }
    func removeTrack(id: UUID) async throws { }
}

@MainActor
private final class DurationTestPlayback: AudioPlayback {
    nonisolated deinit {}

    var status: AudioPlaybackStatus = .idle
    var elapsed: TimeInterval = 0
    var duration: TimeInterval
    var onEvent: (@MainActor @Sendable (AudioPlaybackEvent) -> Void)?
    var onStateChange: (@MainActor @Sendable () -> Void)?

    init(duration: TimeInterval) { self.duration = duration }
    func load(_ track: Track) throws { status = .ready }
    func play() throws { status = .playing }
    func pause() { status = .paused }
    func seek(to seconds: TimeInterval) throws { elapsed = seconds }
    func stop() { status = .idle }
}
