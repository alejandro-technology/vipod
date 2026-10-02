import SwiftUI
import XCTest
@testable import vipod

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class ClassicArtworkPresentationTests: XCTestCase {
    func testImportedArtworkAppearsWhenPlaybackStartsAfterViewMounts() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-ArtworkTone", withExtension: "m4a"))
        let plainFixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-TestTone", withExtension: "mp3"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try FileTrackRepository(storageURL: root)
        let report = try await repository.importTracks(from: [fixture, plainFixture])
        let track = try XCTUnwrap(report.imported.first)
        let plainTrack = try XCTUnwrap(report.imported.last)
        XCTAssertEqual(report.imported.count, 2)
        XCTAssertNotNil(track.artworkFilename)
        XCTAssertNil(plainTrack.artworkFilename)
        let data = try await repository.artworkData(for: track)
        XCTAssertNotNil(data)

        let library = LibraryController(repository: repository)
        await library.load()
        let engine = ArtworkTestPlayback()
        let playback = PlaybackController(engine: engine, tracks: report.imported)
        let probe = ArtworkLoadProbe()
        let view = ClassicPlayerView(library: library, playback: playback, artworkLoader: { track in
            await probe.record(track.id)
            return try? await repository.artworkData(for: track)
        })
        let host = ArtworkTestHost(view: view)
        defer { host.close() }
        // Start from an already-mounted menu, as when the user chooses a song.
        try await Task.sleep(for: .milliseconds(100))
        playback.play(track)

        try await waitForArtwork(in: host, visible: true)
        let requestedIDs = await probe.ids
        XCTAssertEqual(requestedIDs, [track.id], "The view must request artwork for the selected track.")

        try engine.seek(to: 10)
        try await Task.sleep(for: .milliseconds(100))
        let requestsAfterProgress = await probe.ids
        XCTAssertEqual(requestsAfterProgress, [track.id], "Playback ticks must not reload the cover.")
        XCTAssertGreaterThan(host.redPixelCount(), 500)

        playback.next()
        try await waitForArtwork(in: host, visible: false)
        playback.previous()
        try await waitForArtwork(in: host, visible: true)
        let requestsAfterSkipping = await probe.ids
        XCTAssertEqual(requestsAfterSkipping, [track.id, plainTrack.id, track.id])
    }

    func testArtworkAppearsForTrackSelectedBeforeViewMounts() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-ArtworkTone", withExtension: "m4a"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try FileTrackRepository(storageURL: root)
        let report = try await repository.importTracks(from: [fixture])
        let track = try XCTUnwrap(report.imported.first)
        let library = LibraryController(repository: repository)
        await library.load()
        let playback = PlaybackController(engine: ArtworkTestPlayback(), tracks: [track])
        playback.play(track)
        let host = ArtworkTestHost(view: ClassicPlayerView(library: library, playback: playback, artworkLoader: { track in
            try? await repository.artworkData(for: track)
        }))
        defer { host.close() }
        try await waitForArtwork(in: host, visible: true)
    }

    private func waitForArtwork(in host: ArtworkTestHost, visible: Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while (host.redPixelCount() > 500) != visible, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if let attachment = host.attachment() {
            attachment.name = visible ? "Rendered album artwork" : "Track without artwork"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(host.redPixelCount() > 500, visible, "The red cover must follow the selected track, replacing the placeholder only when artwork exists.")
    }
}

@MainActor
private final class ArtworkTestHost {
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

    private func snapshot() -> CGImage? {
        let image: CGImage?
        #if os(macOS)
        hostingView.layoutSubtreeIfNeeded()
        if let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            image = bitmap.cgImage
        } else { image = nil }
        #else
        controller.view.layoutIfNeeded()
        image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }.cgImage
        #endif
        return image
    }

    func attachment() -> XCTAttachment? {
        guard let image = snapshot() else { return nil }
        #if os(macOS)
        return XCTAttachment(image: NSImage(cgImage: image, size: .zero))
        #else
        return XCTAttachment(image: UIImage(cgImage: image))
        #endif
    }

    func redPixelCount() -> Int {
        guard let image = snapshot() else { return 0 }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: pixels.count, by: 4).filter {
                pixels[$0] > 200 && pixels[$0 + 1] < 60 && pixels[$0 + 2] < 60
            }.count
        }
    }
}

private actor ArtworkLoadProbe {
    var ids: [UUID] = []
    func record(_ id: UUID) { ids.append(id) }
}

@MainActor
private final class ArtworkTestPlayback: AudioPlayback {
    nonisolated deinit {}
    var status: AudioPlaybackStatus = .idle
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 120
    var onEvent: (@MainActor @Sendable (AudioPlaybackEvent) -> Void)?
    var onStateChange: (@MainActor @Sendable () -> Void)?
    func load(_ track: Track) throws { elapsed = 0; status = .ready }
    func play() throws { status = .playing; onStateChange?() }
    func pause() { status = .paused; onStateChange?() }
    func seek(to seconds: TimeInterval) throws { elapsed = seconds; onStateChange?() }
    func stop() { status = .idle; onStateChange?() }
}
