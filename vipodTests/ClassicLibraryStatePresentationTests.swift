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
final class ClassicLibraryStatePresentationTests: XCTestCase {
    func testFailedEmptyMusicSubmenuShowsRetryInsteadOfMenuOrSplitPreview() async throws {
        let artist = ClassicPlayerRow(id: "artist", title: "Artist Row", action: .open(.artists))
        let album = ClassicPlayerRow(id: "album", title: "Album Row", action: .open(.albums))
        let song = ClassicPlayerRow(id: "song", title: "Song Row", action: .open(.songs))
        let host = LibraryStatePresentationHost(view: AnyView(browserView(
            rows: [artist, album, song],
            loadFailed: true,
            hasTracks: false,
            shouldShowEmptyLibrary: true,
            usesSplitMenu: true,
            isMainMenu: false,
            preview: preview(track: Track(title: "Preview Track", artist: "Preview Artist", audioFilename: "preview.mp3"))
        )))
        defer { host.close() }

        let rendered = try await waitForRecognizedText(in: host, containing: "Retry Library Load")
        XCTAssertFalse(rendered.containsText("Artist Row"))
        XCTAssertFalse(rendered.containsText("Album Row"))
        XCTAssertFalse(rendered.containsText("Song Row"))
        XCTAssertFalse(rendered.containsText("Preview Track"))
    }

    func testFailedEmptySettingsShowsAirPodsRouteAboveRetryWithoutThemeRows() async throws {
        let host = LibraryStatePresentationHost(view: AnyView(settingsView(
            rows: themeRows,
            loadFailed: true,
            hasTracks: false,
            outputName: "AirPods Pro",
            outputKind: .airPods
        )))
        defer { host.close() }

        let rendered = try await waitForRecognizedText(in: host, containing: "Retry Library Load")
        let routeY = try XCTUnwrap(rendered.first(where: { $0.text.contains("Connected device: AirPods Pro") })?.midY)
        let batteryY = try XCTUnwrap(rendered.first(where: { $0.text.contains("Battery level is unavailable") })?.midY)
        let retryY = try XCTUnwrap(rendered.first(where: { $0.text.contains("Retry Library Load") })?.midY)
        XCTAssertGreaterThan(routeY, retryY, "The connected route detail must render above the retry panel.")
        XCTAssertGreaterThan(batteryY, retryY, "The AirPods battery detail must render above the retry panel.")
        XCTAssertFalse(rendered.containsText("Black iPod"))
        XCTAssertFalse(rendered.containsText("White iPod"))
    }

    func testEmptySettingsWhileLoadingShowsLoadingInsteadOfThemeRows() async throws {
        let host = LibraryStatePresentationHost(view: AnyView(settingsView(
            rows: themeRows,
            isLoading: true,
            loadFailed: false,
            hasTracks: false
        )))
        defer { host.close() }

        let rendered = try await waitForRecognizedText(in: host, containing: "Loading Music")
        XCTAssertFalse(rendered.containsText("Black iPod"))
        XCTAssertFalse(rendered.containsText("White iPod"))
    }

    private var themeRows: [ClassicPlayerRow] {
        [
            ClassicPlayerRow(id: "theme.black", title: "Black iPod", action: .setTheme(.black)),
            ClassicPlayerRow(id: "theme.white", title: "White iPod", action: .setTheme(.white))
        ]
    }

    private func browserView(
        rows: [ClassicPlayerRow],
        loadFailed: Bool,
        hasTracks: Bool,
        shouldShowEmptyLibrary: Bool,
        usesSplitMenu: Bool,
        isMainMenu: Bool,
        preview: MenuArtworkPreview
    ) -> LibraryBrowserView {
        LibraryBrowserView(
            presentation: LibraryBrowserPresentation(
                rows: rows,
                selectedRowID: nil,
                selectedRowTitle: nil,
                theme: .classicBlack,
                reduceMotion: true,
                isImporting: false,
                isLoading: false,
                loadFailed: loadFailed,
                hasTracks: hasTracks,
                shouldShowEmptyLibrary: shouldShowEmptyLibrary,
                usesSplitMenu: usesSplitMenu,
                isMainMenu: isMainMenu,
                isFilterable: false,
                isSongs: false,
                filterText: .constant(""),
                canRemoveSelectedTrack: false,
                summary: nil,
                failures: [],
                failuresExpanded: .constant(false),
                hasLibraryError: false,
                preview: preview
            ),
            actions: LibraryBrowserActions(
                importMusic: {},
                removeSelectedSong: {},
                retryLoad: {},
                activate: { _ in }
            ),
            titleForRow: { $0.title },
            subtitleForRow: { $0.subtitle }
        )
    }

    private func settingsView(
        rows: [ClassicPlayerRow],
        isLoading: Bool = false,
        loadFailed: Bool,
        hasTracks: Bool,
        outputName: String? = nil,
        outputKind: BluetoothDeviceKind? = nil
    ) -> PlayerSettingsView {
        PlayerSettingsView(
            rows: rows,
            selectedRowID: nil,
            theme: .classicBlack,
            reduceMotion: true,
            isImporting: false,
            isLoading: isLoading,
            loadFailed: loadFailed,
            hasTracks: hasTracks,
            summary: nil,
            failures: [],
            failuresExpanded: .constant(false),
            hasLibraryError: false,
            outputName: outputName,
            outputKind: outputKind,
            presentation: PlayerSettingsPresentation(
                isBlackTheme: true,
                isShuffled: false,
                repeatMode: .off,
                preferredBluetoothKind: nil
            ),
            retryAction: {},
            activate: { _ in }
        )
    }

    private func preview(track: Track) -> MenuArtworkPreview {
        MenuArtworkPreview(
            track: track,
            artwork: nil,
            durationText: "1:00",
            hint: "Preview unavailable",
            theme: .classicBlack
        )
    }

    private func waitForRecognizedText(
        in host: LibraryStatePresentationHost,
        containing expectedText: String
    ) async throws -> [RecognizedLine] {
        let deadline = ContinuousClock.now + .seconds(8)
        var latest: [RecognizedLine] = []
        while ContinuousClock.now < deadline {
            latest = try host.recognizedText()
            if latest.containsText(expectedText) { return latest }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("Expected rendered text containing ‘\(expectedText)’; recognized: \(latest.map(\.text))")
        return latest
    }
}

private extension Array where Element == RecognizedLine {
    func containsText(_ text: String) -> Bool {
        contains(where: { $0.text.contains(text) })
    }
}

private struct RecognizedLine {
    let text: String
    let midY: CGFloat
}

@MainActor
private final class LibraryStatePresentationHost {
    nonisolated deinit {}

    #if os(macOS)
    private let window: NSWindow
    private let hostingView: NSHostingView<AnyView>
    #else
    private let window: UIWindow
    private let controller: UIHostingController<AnyView>
    #endif

    init(view: AnyView) {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let renderedView = AnyView(
            view
                .foregroundStyle(iPodTheme.classicBlack.palette.screenText)
                .background(iPodTheme.classicBlack.palette.screen)
                .frame(width: frame.width, height: frame.height)
        )
        #if os(macOS)
        hostingView = NSHostingView(rootView: renderedView)
        window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        #else
        controller = UIHostingController(rootView: renderedView)
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
