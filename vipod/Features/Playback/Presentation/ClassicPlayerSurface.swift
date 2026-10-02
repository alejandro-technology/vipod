import SwiftUI

/// Responsive black body composition with a classic LCD above the broad wheel.
public struct ClassicPlayerSurface<ScreenContent: View>: View {
    public var theme: iPodTheme
    public var screenContent: ScreenContent
    public var browse: (Int) -> Void
    public var select: () -> Void
    public var menu: () -> Void
    public var playPause: () -> Void
    public var next: () -> Void
    public var previous: () -> Void
    public var wheelAccessibilityID: String

    public init(
        theme: iPodTheme = .classicBlack,
        wheelAccessibilityID: String = "wheel",
        @ViewBuilder screen: () -> ScreenContent,
        browse: @escaping (Int) -> Void,
        select: @escaping () -> Void,
        menu: @escaping () -> Void,
        playPause: @escaping () -> Void,
        next: @escaping () -> Void,
        previous: @escaping () -> Void
    ) {
        self.theme = theme
        self.wheelAccessibilityID = wheelAccessibilityID
        self.screenContent = screen()
        self.browse = browse
        self.select = select
        self.menu = menu
        self.playPause = playPause
        self.next = next
        self.previous = previous
    }

    public var body: some View {
        GeometryReader { proxy in
            #if os(macOS)
            let compactLandscape = false
            let contentWidth = min(min(proxy.size.width, proxy.size.height * 420 / 780), 760)
            #else
            let compactLandscape = proxy.size.width > proxy.size.height * 1.2
            let contentWidth = min(proxy.size.width, 760)
            #endif

            Group {
                if compactLandscape {
                    HStack(spacing: 8) {
                        display(width: contentWidth * 0.54, height: proxy.size.height * 0.9)
                        wheel(side: min(proxy.size.height * 0.94, contentWidth * 0.40))
                    }
                } else {
                    VStack(spacing: 0) {
                        display(width: contentWidth * 0.88, height: proxy.size.height * 0.38)
                        // The wheel's artwork is already inset within its square by the
                        // theme's diameter fraction. Give it a full-width square here so
                        // that inset is applied only once, then center it in the space
                        // left below the display.
                        wheel(side: min(contentWidth, proxy.size.height * 0.62), alignment: .center)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
            }
            .frame(width: contentWidth, height: proxy.size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.palette.body)
        }
        .background(theme.palette.body.ignoresSafeArea())
    }

    private func display(width: CGFloat, height: CGFloat) -> some View {
        screenContent
            .padding(.top, min(height * 0.03, 12))
            .frame(width: width, height: height, alignment: .top)
            .clipped()
    }

    private func wheel(side: CGFloat, alignment: Alignment = .top) -> some View {
        ClickWheel(
            theme: theme,
            accessibilityID: wheelAccessibilityID,
            browse: browse,
            select: select,
            menu: menu,
            playPause: playPause,
            next: next,
            previous: previous
        )
        .frame(width: side, height: side)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
