import SwiftUI

struct NowPlayingView: View {
    let track: Track?
    let artwork: Image?
    let elapsed: TimeInterval
    let duration: TimeInterval
    let elapsedText: String
    let durationText: String
    let isSeeking: Bool
    let hasPlaybackError: Bool
    let theme: iPodTheme
    let onSeek: (TimeInterval) -> Void
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    RetroArtworkFrame(artwork: artwork, theme: theme)
                        .frame(width: 78, height: 78)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track?.title ?? String(localized: "Nothing Playing"))
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(2)
                            .accessibilityIdentifier("nowPlaying.title")
                        Text(track?.artist ?? String(localized: "Choose a song from Music"))
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Text(track?.album ?? "")
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)

                VStack(spacing: 1) {
                    Slider(
                        value: Binding(
                            get: { min(max(elapsed, 0), max(duration, 1)) },
                            set: onSeek
                        ),
                        in: 0...max(duration, 1)
                    )
                    .tint(theme.palette.selection)
                    .disabled(duration <= 0)
                    .accessibilityLabel(String(localized: "Playback position"))
                    .accessibilityHint(duration > 0
                        ? String(localized: "Adjust playback position")
                        : String(localized: "Seeking is unavailable until the track duration is known."))
                    RetroPlaybackProgress(
                        progress: duration > 0 ? elapsed / duration : 0,
                        elapsed: elapsedText,
                        duration: durationText,
                        theme: theme
                    )
                }
                .padding(.horizontal, 10)

                Text(isSeeking
                    ? String(localized: "Rotate to seek · Select to finish")
                    : String(localized: "Select to enable wheel seeking"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.palette.secondaryText)
                    .frame(minHeight: 18)
                    .accessibilityIdentifier("nowPlaying.seekHint")
                if hasPlaybackError {
                    Button(String(localized: "Playback needs attention · Try Again"), action: onRetry)
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHint(String(localized: "Retry playing the current track"))
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 5)
    }
}
