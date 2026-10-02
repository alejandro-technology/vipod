#if os(macOS)
import AppKit
import SwiftUI

/// Applies portrait sizing only to the window hosting the app's player root view.
struct PortraitPlayerWindow: NSViewRepresentable {
    static let defaultSize = CGSize(width: 420, height: 780)
    static let minimumSize = CGSize(width: 320, height: 320 * 780 / 420.0)

    @Binding var minimumContentSize: CGSize

    func makeNSView(context: Context) -> WindowAttachmentView {
        WindowAttachmentView()
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        nsView.onMinimumContentSizeChange = { $minimumContentSize.wrappedValue = $0 }
    }

    final class WindowAttachmentView: NSView {
        private weak var configuredWindow: NSWindow?
        var onMinimumContentSizeChange: ((CGSize) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== configuredWindow else { return }
            configuredWindow = window
            // Let SwiftUI finish attaching and sizing the hosting view before writing
            // native window constraints; the root modifier supplies the same minimum.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                self.configure(window)
            }
        }

        private func configure(_ window: NSWindow) {
            window.contentAspectRatio = defaultSize

            let currentSize = window.contentView?.frame.size ?? window.contentRect(forFrameRect: window.frame).size
            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            let fittedMinimumSize: CGSize
            if let visibleFrame {
                let visibleContentRect = window.contentRect(forFrameRect: visibleFrame)
                let scale = min(
                    1,
                    min(visibleContentRect.width / defaultSize.width, visibleContentRect.height / defaultSize.height)
                )
                fittedMinimumSize = CGSize(
                    width: min(minimumSize.width, defaultSize.width * scale),
                    height: min(minimumSize.height, defaultSize.height * scale)
                )
            } else {
                fittedMinimumSize = minimumSize
            }

            onMinimumContentSizeChange?(fittedMinimumSize)
            window.contentMinSize = fittedMinimumSize

            if currentSize.width > currentSize.height * defaultSize.width / defaultSize.height,
               let visibleFrame {
                let visibleContentRect = window.contentRect(forFrameRect: visibleFrame)
                let scale = min(
                    1,
                    min(visibleContentRect.width / defaultSize.width, visibleContentRect.height / defaultSize.height)
                )
                window.setContentSize(CGSize(width: defaultSize.width * scale, height: defaultSize.height * scale))
            }
        }
    }
}

private struct PortraitPlayerWindowModifier: ViewModifier {
    @State private var minimumContentSize = PortraitPlayerWindow.minimumSize

    func body(content: Content) -> some View {
        content
            .frame(minWidth: minimumContentSize.width, minHeight: minimumContentSize.height)
            .background(PortraitPlayerWindow(minimumContentSize: $minimumContentSize))
    }
}

extension View {
    func portraitPlayerWindow() -> some View {
        modifier(PortraitPlayerWindowModifier())
    }
}
#endif
