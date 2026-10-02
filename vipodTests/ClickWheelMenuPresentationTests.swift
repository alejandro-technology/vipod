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
final class ClickWheelMenuPresentationTests: XCTestCase {
    func testMenuLabelRendersWithoutTruncationAtLargeWheelSizes() async throws {
        for (diameter, theme, appearance) in [
            (CGFloat(430), iPodTheme.classicBlack, "black"),
            (CGFloat(430), iPodTheme.classicWhite, "white"),
            (CGFloat(760), iPodTheme.classicBlack, "black"),
            (CGFloat(760), iPodTheme.classicWhite, "white")
        ] {
            let host = ClickWheelMenuPresentationHost(diameter: diameter, theme: theme)
            defer { host.close() }

            let recognized = try await waitForMenu(in: host)
            XCTAssertTrue(
                recognized.contains { $0.localizedCaseInsensitiveContains("MENU") },
                "Vision must recognize the rendered MENU text at \(diameter)pt in the \(appearance) appearance; recognized: \(recognized)"
            )

            if let attachment = host.attachment() {
                attachment.name = "Click wheel MENU — \(Int(diameter))pt, \(appearance)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func waitForMenu(in host: ClickWheelMenuPresentationHost) async throws -> [String] {
        let deadline = ContinuousClock.now + .seconds(8)
        var recognized: [String] = []
        while ContinuousClock.now < deadline {
            recognized = try host.recognizedText()
            if recognized.contains(where: { $0.localizedCaseInsensitiveContains("MENU") }) {
                return recognized
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("Expected Vision to recognize rendered MENU text; recognized: \(recognized)")
        return recognized
    }
}

@MainActor
private final class ClickWheelMenuPresentationHost {
    nonisolated deinit {}

    #if os(macOS)
    private let window: NSWindow
    private let hostingView: NSHostingView<ClickWheel>
    #else
    private let window: UIWindow
    private let controller: UIHostingController<ClickWheel>
    #endif

    init(diameter: CGFloat, theme: iPodTheme) {
        let frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let view = ClickWheel(
            theme: theme,
            browse: { _ in },
            select: {},
            menu: {},
            playPause: {},
            next: {},
            previous: {}
        )
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

    func attachment() -> XCTAttachment? {
        guard let image = snapshot() else { return nil }
        #if os(macOS)
        return XCTAttachment(image: NSImage(cgImage: image, size: .zero))
        #else
        return XCTAttachment(image: UIImage(cgImage: image))
        #endif
    }

    func recognizedText() throws -> [String] {
        guard let image = snapshot() else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private func snapshot() -> CGImage? {
        #if os(macOS)
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap.cgImage
        #else
        controller.view.layoutIfNeeded()
        return UIGraphicsImageRenderer(bounds: controller.view.bounds).image { [self] _ in
            self.controller.view.drawHierarchy(in: self.controller.view.bounds, afterScreenUpdates: true)
        }.cgImage
        #endif
    }
}
