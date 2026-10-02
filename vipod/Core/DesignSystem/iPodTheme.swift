import SwiftUI

/// Semantic colors and geometry for the embedded iPod Classic-inspired interface.
public struct iPodTheme: Sendable {
    public struct Palette: Sendable {
        public let body: Color
        public let wheel: Color
        public let wheelEdge: Color
        public let screen: Color
        public let screenText: Color
        public let secondaryText: Color
        public let selection: Color
        public let selectionText: Color
        public let separator: Color
        public let controlText: Color

        public init(
            body: Color,
            wheel: Color,
            wheelEdge: Color,
            screen: Color,
            screenText: Color,
            secondaryText: Color,
            selection: Color,
            selectionText: Color = .white,
            separator: Color,
            controlText: Color
        ) {
            self.body = body
            self.wheel = wheel
            self.wheelEdge = wheelEdge
            self.screen = screen
            self.screenText = screenText
            self.secondaryText = secondaryText
            self.selection = selection
            self.selectionText = selectionText
            self.separator = separator
            self.controlText = controlText
        }
    }

    public let palette: Palette
    public let wheelDiameterFraction: CGFloat
    public let wheelCenterFraction: CGFloat
    public let menuRowHeight: CGFloat

    public init(
        palette: Palette,
        wheelDiameterFraction: CGFloat = 0.76,
        wheelCenterFraction: CGFloat = 0.27,
        menuRowHeight: CGFloat = 42
    ) {
        self.palette = palette
        self.wheelDiameterFraction = wheelDiameterFraction
        self.wheelCenterFraction = wheelCenterFraction
        self.menuRowHeight = menuRowHeight
    }

    /// The default 2008 Classic appearance: black body and wheel, light LCD, blue selection.
    public static let classicBlack = iPodTheme(
        palette: Palette(
            body: Color(red: 0.015, green: 0.015, blue: 0.018),
            wheel: Color(red: 0.075, green: 0.075, blue: 0.08),
            wheelEdge: Color(red: 0.15, green: 0.15, blue: 0.16),
            screen: Color(red: 0.88, green: 0.90, blue: 0.91),
            screenText: Color(red: 0.08, green: 0.09, blue: 0.10),
            secondaryText: Color(red: 0.34, green: 0.36, blue: 0.38),
            selection: Color(red: 0.20, green: 0.43, blue: 0.72),
            separator: Color(red: 0.70, green: 0.72, blue: 0.73),
            controlText: Color(red: 0.78, green: 0.79, blue: 0.80)
        )
    )

    /// Silver-body palette for the same LCD interface.
    public static let classicWhite = iPodTheme(
        palette: Palette(
            body: Color(red: 0.78, green: 0.79, blue: 0.80),
            wheel: Color(red: 0.90, green: 0.90, blue: 0.91),
            wheelEdge: Color(red: 0.68, green: 0.69, blue: 0.70),
            screen: Color(red: 0.88, green: 0.90, blue: 0.91),
            screenText: Color(red: 0.08, green: 0.09, blue: 0.10),
            secondaryText: Color(red: 0.34, green: 0.36, blue: 0.38),
            selection: Color(red: 0.20, green: 0.43, blue: 0.72),
            separator: Color(red: 0.70, green: 0.72, blue: 0.73),
            controlText: Color(red: 0.30, green: 0.31, blue: 0.32)
        )
    )
}
