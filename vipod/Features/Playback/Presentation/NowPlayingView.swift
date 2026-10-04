import SwiftUI

struct NowPlayingView: View {
    let track: Track?
    let previousTrack: Track?
    let nextTrack: Track?
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
        VStack(spacing: 6) {
            ScrollView {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        RetroArtworkFrame(artwork: artwork, theme: theme)
                            .frame(width: 96, height: 96)
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
                        HStack {
                            Text(elapsedText)
                                .accessibilityIdentifier("nowPlaying.elapsed")
                            Spacer(minLength: 8)
                            Text(durationText)
                                .accessibilityIdentifier("nowPlaying.duration")
                        }
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.palette.secondaryText)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(String(localized: "Elapsed and total time"))
                        .accessibilityValue(String.localizedStringWithFormat(
                            String(localized: "Elapsed %@, total %@"), elapsedText, durationText
                        ))
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
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)

            HStack(alignment: .bottom, spacing: 8) {
                neighborBlock(track: previousTrack, title: String(localized: "Previous"), alignment: .leading, identifier: "nowPlaying.previous")
                neighborBlock(track: nextTrack, title: String(localized: "Next"), alignment: .trailing, identifier: "nowPlaying.next")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .padding(.top, 5)
    }

    private func neighborBlock(track: Track?, title: String, alignment: HorizontalAlignment, identifier: String) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.palette.secondaryText)
            Text(track?.title ?? "—")
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(track?.artist ?? "—")
                .font(.system(size: 9))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(track.map {
            String.localizedStringWithFormat(String(localized: "%@, %@"), $0.title, $0.artist)
        } ?? String(localized: "Unavailable"))
        .accessibilityIdentifier(identifier)
    }
}
