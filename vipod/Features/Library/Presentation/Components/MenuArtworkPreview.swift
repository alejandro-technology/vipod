import SwiftUI

struct MenuArtworkPreview: View {
    let track: Track?
    let artwork: Image?
    let durationText: String
    let hint: String
    let theme: iPodTheme

    var body: some View {
        GeometryReader { proxy in
            // Reserve space for a two-line title, artist, and duration even on short panels.
            let metadataHeight: CGFloat = 82
            let imageSide = min(max(0, proxy.size.width - 12), max(0, proxy.size.height - metadataHeight - 12))
            VStack(spacing: 5) {
                RetroArtworkFrame(artwork: artwork, theme: theme)
                    .frame(width: imageSide, height: imageSide)
                if let track {
                    Text(track.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(track.artist)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    Text(String.localizedStringWithFormat(String(localized: "Duration: %@"), durationText))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel(String.localizedStringWithFormat(String(localized: "Duration %@"), durationText))
                        .accessibilityIdentifier("menu.trackDuration")
                } else {
                    Text(hint)
                        .font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(theme.palette.screenText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 7)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("menu.artworkPreview")
        }
    }
}
