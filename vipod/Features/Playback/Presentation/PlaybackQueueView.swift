import SwiftUI

struct PlaybackQueueView: View {
    let tracks: [Track]
    let currentTrackID: UUID?
    let selectedTrackID: UUID?
    let theme: iPodTheme
    let select: (UUID) -> Void
    let playTrack: (UUID) -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    private var selectedIndex: Int? {
        selectedTrackID.flatMap { id in tracks.firstIndex(where: { $0.id == id }) }
    }

    var body: some View {
        VStack(spacing: 8) {
            if tracks.isEmpty {
                Text(String(localized: "The playback queue is empty."))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("queue.empty")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            HStack(spacing: 8) {
                                Button { select(track.id) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title).font(.system(size: 15, weight: selectedTrackID == track.id ? .bold : .regular))
                                        Text(track.artist).font(.system(size: 11)).foregroundStyle(theme.palette.secondaryText)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(track.title)
                                .accessibilityValue(currentTrackID == track.id ? String(localized: "Now Playing") : (selectedTrackID == track.id ? String(localized: "Selected") : ""))
                                .accessibilityIdentifier("queue.track.\(track.id.uuidString)")
                                .accessibilityHint(String.localizedStringWithFormat(String(localized: "Queue position %lld of %lld"), index + 1, tracks.count))
                                if currentTrackID == track.id {
                                    Text(String(localized: "Now Playing"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .accessibilityIdentifier("queue.currentTrack")
                                }
                                Button(String(localized: "Play"), systemImage: "play.fill") { playTrack(track.id) }
                                    .accessibilityLabel(String.localizedStringWithFormat(String(localized: "Play %@"), track.title))
                                    .accessibilityIdentifier("queue.play.\(track.id.uuidString)")
                            }
                            .foregroundStyle(selectedTrackID == track.id ? theme.palette.selectionText : theme.palette.screenText)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 48)
                            .background(selectedTrackID == track.id ? theme.palette.selection : .clear)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                HStack(spacing: 12) {
                    Button(String(localized: "Move Up"), systemImage: "arrow.up", action: moveUp)
                        .accessibilityIdentifier("queue.moveUp")
                        .disabled(selectedIndex == nil || selectedIndex == 0)
                    Button(String(localized: "Move Down"), systemImage: "arrow.down", action: moveDown)
                        .accessibilityIdentifier("queue.moveDown")
                        .disabled(selectedIndex == nil || selectedIndex == tracks.count - 1)
                    Button(String(localized: "Remove from Queue"), systemImage: "minus.circle", role: .destructive, action: remove)
                        .accessibilityIdentifier("queue.remove")
                        .disabled(selectedIndex == nil)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
    }
}
