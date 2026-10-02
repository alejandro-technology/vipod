import SwiftUI
import Vision
import XCTest
@testable import vipod

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class ClassicPlayerStatusPresentationTests: XCTestCase {
    func testMenuPreviewUpdatesDisplayedDurationAfterTrackChange() async throws {
        let first = Track(title: "First Song", artist: "Test Artist", album: "Test Album", duration: 80, audioFilename: "first.mp3")
        let second = Track(title: "Second Song", artist: "Test Artist", album: "Test Album", duration: 150, audioFilename: "second.mp3")
        let library = LibraryController(repository: PresentationTestRepository())
        let engine = PresentationTestPlayback()
        let playback = PlaybackController(engine: engine, tracks: [first, second])
        playback.play(first)
        let host = DurationPresentationHost(view: ClassicPlayerView(library: library, playback: playback))
        defer { host.close() }

        let firstText = try await waitForRecognizedText(in: host, containing: "1:20")
        XCTAssertTrue(firstText.contains(where: { $0.text.contains("Playing") }), "The playback status must remain visible in the header.")
        XCTAssertTrue(firstText.contains(where: { $0.text.contains("First Song") }))
        let artistY = try XCTUnwrap(firstText.first(where: { $0.text.contains("Test Artist") })?.midY)
        let durationY = try XCTUnwrap(firstText.first(where: { $0.text.contains("1:20") })?.midY)
        XCTAssertLessThan(durationY, artistY, "The duration must render beneath the artist in the artwork preview.")

        playback.next()
        let secondText = try await waitForRecognizedText(in: host, containing: "2:30")
        XCTAssertTrue(secondText.contains(where: { $0.text.contains("Second Song") }))
    }

    #if os(macOS)
    func testMountedHeaderShowsAirPodsAndManualSpeakerStatus() async throws {
        let defaultsSuite = "ClassicPlayerStatusPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let provider = MutableAudioOutputProvider(output: BluetoothAudioOutput(uid: "test-route", name: "AirPods Pro"))
        let monitor = AudioConnectionMonitor(defaults: defaults, outputProvider: { provider.output })
        let track = Track(title: "Status Song", artist: "Test Artist", duration: 80, audioFilename: "status.mp3")
        let playback = PlaybackController(engine: PresentationTestPlayback(), tracks: [track])
        playback.play(track)
        let library = LibraryController(repository: PresentationTestRepository())
        let host = DurationPresentationHost(view: ClassicPlayerView(library: library, playback: playback, audioConnection: monitor))
        defer { host.close() }

        let airPodsText = try await waitForRecognizedText(in: host, containing: "Status Song")
        XCTAssertTrue(monitor.status?.accessibilityLabel.contains("AirPods connected") == true)
        if let attachment = host.attachment() {
            attachment.name = "Classic player with AirPods connection status"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(airPodsText.contains(where: { $0.text.contains("Playing") }), "The playback status must remain visible beside the song title.")

        monitor.setPreferredDeviceKind(.speaker)
        XCTAssertTrue(monitor.status?.accessibilityLabel.contains("Bluetooth speaker connected") == true)
        try await Task.sleep(for: .milliseconds(100))
        if let attachment = host.attachment() {
            attachment.name = "Classic player after manually assigning Bluetooth speaker status"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    #endif

    private func waitForRecognizedText(
        in host: DurationPresentationHost,
        containing expectedText: String
    ) async throws -> [RecognizedLine] {
        let deadline = ContinuousClock.now + .seconds(8)
        var latest: [RecognizedLine] = []
        while ContinuousClock.now < deadline {
            latest = try host.recognizedText()
            if latest.contains(where: { $0.text.contains(expectedText) }) { return latest }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("Expected rendered text containing ‘\(expectedText)’; recognized: \(latest.map(\.text))")
        return latest
    }
}

private struct RecognizedLine {
    let text: String
    let midY: CGFloat
}

@MainActor
private final class DurationPresentationHost {
    nonisolated deinit {}

    #if os(macOS)
    private let window: NSWindow
    private let hostingView: NSHostingView<ClassicPlayerView>
    #else
    private let window: UIWindow
    private let controller: UIHostingController<ClassicPlayerView>
    #endif

    init(view: ClassicPlayerView) {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        #if os(macOS)
        hostingView = NSHostingView(rootView: view)
        window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        #else
        controller = UIHostingController(rootView: view)
        window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        #endif
    }

    func close() {
        #if os(macOS)
        window.close()
        #else
        window.isHidden = true
        window.rootViewController = nil
        #endif
    }

    #if os(macOS)
    func attachment() -> XCTAttachment? {
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let image = bitmap.cgImage else { return nil }
        return XCTAttachment(image: NSImage(cgImage: image, size: .zero))
    }
    #endif

    func recognizedText() throws -> [RecognizedLine] {
        #if os(macOS)
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return [] }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let image = bitmap.cgImage else { return [] }
        #else
        controller.view.layoutIfNeeded()
        guard let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image(
            actions: { [self] _ in self.controller.view.drawHierarchy(in: self.controller.view.bounds, afterScreenUpdates: true) }
        ).cgImage else { return [] }
        #endif

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return RecognizedLine(text: text, midY: observation.boundingBox.midY)
        }
    }
}

private actor PresentationTestRepository: TrackRepository {
    func tracks() async throws -> [Track] { [] }
    func importTracks(from urls: [URL]) async throws -> TrackImportReport { await TrackImportReport(imported: []) }
    func removeTrack(id: UUID) async throws { }
}

#if os(macOS)
@MainActor
private final class MutableAudioOutputProvider {
    nonisolated deinit {}

    var output: BluetoothAudioOutput?

    init(output: BluetoothAudioOutput?) { self.output = output }
}
#endif

@MainActor
private final class PresentationTestPlayback: AudioPlayback {
    nonisolated deinit {}

    var status: AudioPlaybackStatus = .idle
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var onEvent: (@MainActor @Sendable (AudioPlaybackEvent) -> Void)?
    var onStateChange: (@MainActor @Sendable () -> Void)?

    func load(_ track: Track) throws {
        duration = track.duration ?? 0
        elapsed = 0
        status = .ready
    }
    func play() throws { status = .playing; onStateChange?() }
    func pause() { status = .paused; onStateChange?() }
    func seek(to seconds: TimeInterval) throws { elapsed = seconds; onStateChange?() }
    func stop() { status = .idle; onStateChange?() }
}
