#if os(macOS)
import AppKit
import SwiftUI
import Vision
import XCTest
@testable import vipod

@MainActor
final class PortraitPlayerWindowTests: XCTestCase {
    func testAttachingPortraitRootNormalizesRestoredLandscapeWindow() async throws {
        let host = PlayerWindowHost(size: CGSize(width: 900, height: 500), portraitConstrained: true)
        defer { host.close() }
        await host.settle()

        XCTAssertEqual(host.window.contentAspectRatio.width / host.window.contentAspectRatio.height, 420.0 / 780.0, accuracy: 0.001)
        XCTAssertGreaterThan(host.window.contentMinSize.width, 0)
        XCTAssertGreaterThan(host.window.contentMinSize.height, 0)
        XCTAssertEqual(host.window.contentMinSize.width, PortraitPlayerWindow.minimumSize.width, accuracy: 1)
        XCTAssertEqual(host.window.contentMinSize.height, PortraitPlayerWindow.minimumSize.height, accuracy: 1)
        XCTAssertLessThan(host.window.contentView!.frame.width, host.window.contentView!.frame.height)

        let recognized = try await host.waitForText("DISPLAY")
        XCTAssertTrue(recognized.contains { $0.localizedCaseInsensitiveContains("DISPLAY") })
        let attachment = try XCTUnwrap(host.attachment())
        attachment.name = "Portrait player window — restored landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAttachingPortraitRootSetsContentConstraintsForNewWindow() async {
        let host = PlayerWindowHost(size: PortraitPlayerWindow.defaultSize, portraitConstrained: true)
        defer { host.close() }
        await host.settle()

        XCTAssertEqual(host.window.contentAspectRatio, PortraitPlayerWindow.defaultSize)
        XCTAssertGreaterThan(host.window.contentMinSize.width, 0)
        XCTAssertGreaterThan(host.window.contentMinSize.height, 0)
        XCTAssertEqual(host.window.contentMinSize.width, PortraitPlayerWindow.minimumSize.width, accuracy: 1)
        XCTAssertEqual(host.window.contentMinSize.height, PortraitPlayerWindow.minimumSize.height, accuracy: 1)
    }

    func testWideHostKeepsDisplayAboveWheelMenuWithoutWindowConstraint() async throws {
        let host = PlayerWindowHost(size: CGSize(width: 1_000, height: 600), portraitConstrained: false)
        defer { host.close() }
        await host.settle()

        let observations = try await host.waitForDisplayAboveMenu()
        XCTAssertGreaterThan(observations.display.boundingBox.midY, observations.menu.boundingBox.midY)

        let attachment = try XCTUnwrap(host.attachment())
        attachment.name = "Portrait player layout — wide host"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class PlayerWindowHost {
    nonisolated deinit {}

    let window: NSWindow
    private let hostingView: NSHostingView<AnyView>

    init(size: CGSize, portraitConstrained: Bool) {
        let player = ClassicPlayerSurface(
            wheelAccessibilityID: "portrait-test-wheel",
            screen: {
                Text("DISPLAY")
                    .font(.system(size: 30, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
                    .foregroundStyle(iPodTheme.classicBlack.palette.screenText)
                    .background(iPodTheme.classicBlack.palette.screen)
            },
            browse: { _ in },
            select: {},
            menu: {},
            playPause: {},
            next: {},
            previous: {}
        )
        let root = portraitConstrained ? AnyView(player.portraitPlayerWindow()) : AnyView(player)
        hostingView = NSHostingView(rootView: root)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
    }

    func settle() async {
        hostingView.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
        hostingView.layoutSubtreeIfNeeded()
    }

    func close() {
        window.close()
    }

    func attachment() -> XCTAttachment? {
        guard let image = snapshot() else { return nil }
        return XCTAttachment(image: NSImage(cgImage: image, size: .zero))
    }

    func waitForText(_ text: String) async throws -> [String] {
        let deadline = ContinuousClock.now + .seconds(8)
        var strings: [String] = []
        while ContinuousClock.now < deadline {
            strings = try recognizedText().compactMap { $0.topCandidates(1).first?.string }
            if strings.contains(where: { $0.localizedCaseInsensitiveContains(text) }) { return strings }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("Vision did not recognize \(text); recognized: \(strings)")
        return strings
    }

    func waitForDisplayAboveMenu() async throws -> (display: VNRecognizedTextObservation, menu: VNRecognizedTextObservation) {
        let deadline = ContinuousClock.now + .seconds(8)
        var observations: [VNRecognizedTextObservation] = []
        while ContinuousClock.now < deadline {
            observations = try recognizedText()
            if let display = observations.first(where: { $0.topCandidates(1).first?.string.localizedCaseInsensitiveContains("DISPLAY") == true }),
               let menu = observations.first(where: { $0.topCandidates(1).first?.string.localizedCaseInsensitiveContains("MENU") == true }) {
                return (display, menu)
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("Vision did not recognize DISPLAY above the rendered MENU text.")
        throw NSError(domain: "PortraitPlayerWindowTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Required player labels were not recognized."])
    }

    private func recognizedText() throws -> [VNRecognizedTextObservation] {
        guard let image = snapshot() else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results ?? []
    }

    private func snapshot() -> CGImage? {
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap.cgImage
    }
}
#endif
