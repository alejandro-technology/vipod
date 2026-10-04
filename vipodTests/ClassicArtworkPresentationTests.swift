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
    func testArtworkFillsCenteredSquareAcrossSourceAspectRatios() throws {
        let cases = [(1000, 562), (300, 300), (500, 500), (300, 500), (4000, 2248)]
        let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)

        for (sourceWidth, sourceHeight) in cases {
            let image = try XCTUnwrap(markedImage(width: sourceWidth, height: sourceHeight, color: red, markerColor: cyan))
            let frameSide: CGFloat = 78
            let host = ArtworkFrameTestHost(artwork: Image(decorative: image, scale: 1), frameSide: frameSide)
            defer { host.close() }

            let snapshot = try XCTUnwrap(host.snapshot())
            let redBounds = try XCTUnwrap(host.redBounds(in: snapshot), "Synthetic artwork should render.")
            let cyanBounds = try XCTUnwrap(host.cyanBounds(in: snapshot), "The centered artwork marker should render.")
            let markerBounds = try XCTUnwrap(host.greenBounds(in: snapshot), "The fixed square marker should render.")
            let squareBounds = markerBounds.insetBy(dx: markerBounds.width / frameSide, dy: markerBounds.height / frameSide)
            let tolerance = max(2, markerBounds.width / frameSide * 2)

            XCTAssertEqual(redBounds.minX, squareBounds.minX, accuracy: tolerance, "Artwork should fill the square horizontally for \(sourceWidth)x\(sourceHeight).")
            XCTAssertEqual(redBounds.maxX, squareBounds.maxX, accuracy: tolerance, "Artwork should fill the square horizontally for \(sourceWidth)x\(sourceHeight).")
            XCTAssertEqual(redBounds.minY, squareBounds.minY, accuracy: tolerance, "Artwork should fill the square vertically for \(sourceWidth)x\(sourceHeight).")
            XCTAssertEqual(redBounds.maxY, squareBounds.maxY, accuracy: tolerance, "Artwork should fill the square vertically for \(sourceWidth)x\(sourceHeight).")
            XCTAssertEqual(cyanBounds.midX, squareBounds.midX, accuracy: tolerance, "The centered source marker should remain centered horizontally.")
            XCTAssertEqual(cyanBounds.midY, squareBounds.midY, accuracy: tolerance, "The centered source marker should remain centered vertically.")
        }
    }

    private func markedImage(width: Int, height: Int, color: CGColor, markerColor: CGColor) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(color)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context?.setFillColor(markerColor)
        context?.fill(CGRect(x: width * 2 / 5, y: height * 2 / 5, width: width / 5, height: height / 5))
        return context?.makeImage()
    }

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
private final class ArtworkFrameTestHost {
    nonisolated deinit {}
    static let hostSide: CGFloat = 180
    #if os(macOS)
    private let window: NSWindow
    private let hostingView: NSHostingView<AnyView>
    #else
    private let window: UIWindow
    private let controller: UIHostingController<AnyView>
    #endif

    init(artwork: Image, frameSide: CGFloat) {
        let content = AnyView(
            ZStack {
                Color(red: 0, green: 0, blue: 1)
                RetroArtworkFrame(artwork: artwork)
                    .frame(width: frameSide, height: frameSide)
                    .overlay(Rectangle().stroke(Color(red: 0, green: 1, blue: 0), lineWidth: 2))
            }
            .frame(width: Self.hostSide, height: Self.hostSide)
        )
        let frame = CGRect(x: 0, y: 0, width: Self.hostSide, height: Self.hostSide)
        #if os(macOS)
        hostingView = NSHostingView(rootView: content)
        window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        #else
        controller = UIHostingController(rootView: content)
        window = UIWindow(frame: frame)
        window.rootViewController = controller
        controller.view.frame = frame
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

    func snapshot() -> CGImage? {
        #if os(macOS)
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap.cgImage
        #else
        controller.view.layoutIfNeeded()
        return UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }.cgImage
        #endif
    }

    func redBounds(in image: CGImage) -> CGRect? {
        colorBounds(in: image) { red, green, blue in red > 200 && green < 60 && blue < 60 }
    }

    func greenBounds(in image: CGImage) -> CGRect? {
        colorBounds(in: image) { red, green, blue in green > 120 && red < 100 && blue < 100 }
    }

    func cyanBounds(in image: CGImage) -> CGRect? {
        colorBounds(in: image) { red, green, blue in green > 200 && blue > 200 && red < 60 }
    }

    private func colorBounds(in image: CGImage, matches: (UInt8, UInt8, UInt8) -> Bool) -> CGRect? {
        let bytes = pixelBytes(image)
        var minX = image.width
        var minY = image.height
        var maxX = -1
        var maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = (y * image.width + x) * 4
                guard matches(bytes[offset], bytes[offset + 1], bytes[offset + 2]) else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: image.height - maxY - 1, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func pixelBytes(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
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
