import SwiftUI

/// LCD header containing a screen title and compact status text.
public struct RetroTitleStatusBar: View {
    public let title: String
    public var status: String?
    public var theme: iPodTheme
    public var connectionSymbol: String?
    public var connectionLabel: String?

    public init(
        title: String,
        status: String? = nil,
        theme: iPodTheme = .classicBlack,
        connectionSymbol: String? = nil,
        connectionLabel: String? = nil
    ) {
        self.title = title
        self.status = status
        self.theme = theme
        self.connectionSymbol = connectionSymbol
        self.connectionLabel = connectionLabel
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
            if let status {
                Text(status)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .accessibilityLabel(status)
            }
            if let connectionSymbol {
                Group {
                    if connectionSymbol == "antenna.radiowaves.left.and.right" {
                        BluetoothGlyph()
                            .stroke(theme.palette.screenText, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 10, height: 15)
                    } else {
                        Image(systemName: connectionSymbol)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(connectionLabel ?? String(localized: "Audio connection status"))
                .accessibilityIdentifier("classic.connectionStatus")
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
        }
        .foregroundStyle(theme.palette.screenText)
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(theme.palette.screen.opacity(0.96))
        .overlay(alignment: .bottom) { theme.palette.separator.frame(height: 1) }
        .accessibilityElement(children: .contain)
    }
}

private struct BluetoothGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + rect.width * 0.5
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.28))
        path.addLine(to: CGPoint(x: x, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.72))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        path.addLine(to: CGPoint(x: x, y: rect.minY))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.27))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.9, y: rect.minY + rect.height * 0.82))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.73))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.9, y: rect.minY + rect.height * 0.18))
        return path
    }
}

/// One classic LCD menu row; selection is communicated by both color and weight.
public struct RetroMenuRow: View {
    public let title: String
    public var subtitle: String?
    public var isSelected: Bool
    public var theme: iPodTheme
    public var action: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        theme: iPodTheme = .classicBlack,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.theme = theme
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("›").font(.system(size: 23, weight: .regular, design: .rounded))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(isSelected ? theme.palette.selectionText : theme.palette.screenText)
            .padding(.horizontal, 10)
            .frame(minHeight: max(theme.menuRowHeight, 44))
            .background(isSelected ? theme.palette.selection : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? String(localized: "Selected") : "")
        .accessibilityHint(subtitle ?? "")
    }
}

/// Artwork presentation frame that falls back to a neutral, licensed-asset-free placeholder.
public struct RetroArtworkFrame: View {
    public let artwork: Image?
    public var theme: iPodTheme

    public init(artwork: Image? = nil, theme: iPodTheme = .classicBlack) {
        self.artwork = artwork
        self.theme = theme
    }

    public var body: some View {
        Group {
            if let artwork {
                artwork.resizable().scaledToFill()
            } else {
                Rectangle().fill(theme.palette.separator.opacity(0.35))
                    .overlay {
                        Text(String(localized: "No Artwork"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.palette.secondaryText)
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.palette.separator, lineWidth: 1))
        .accessibilityLabel(artwork == nil ? String(localized: "No Artwork") : String(localized: "Album Artwork"))
    }
}

/// Passive playback progress display. Seeking intent can be added by a containing feature.
public struct RetroPlaybackProgress: View {
    public let progress: Double
    public let elapsed: String
    public let duration: String
    public var theme: iPodTheme

    public init(progress: Double, elapsed: String, duration: String, theme: iPodTheme = .classicBlack) {
        self.progress = progress
        self.elapsed = elapsed
        self.duration = duration
        self.theme = theme
    }

    public var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.palette.separator)
                    Capsule().fill(theme.palette.selection)
                        .frame(width: geometry.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(height: 4)
            HStack {
                Text(elapsed)
                Spacer()
                Text(duration)
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(theme.palette.screenText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Playback progress"))
        .accessibilityValue("\(elapsed) of \(duration)")
    }
}
