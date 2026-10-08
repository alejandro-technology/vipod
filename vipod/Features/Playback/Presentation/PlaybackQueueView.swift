import SwiftUI

struct PlaybackQueueView: View {
    let tracks: [Track]
    let currentTrackID: UUID?
    let selectedTrackID: UUID?
    let theme: iPodTheme
    let select: (UUID) -> Void
    var reduceMotion = false

    var body: some View {
        VStack(spacing: 8) {
            if tracks.isEmpty {
                Text(String(localized: "The playback queue is empty."))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("queue.empty")
            } else {
                ScrollViewReader { proxy in
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
                            }
                            .foregroundStyle(selectedTrackID == track.id ? theme.palette.selectionText : theme.palette.screenText)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 48)
                            .background(selectedTrackID == track.id ? theme.palette.selection : .clear)
                            .id(track.id)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedTrackID) { _, id in
                    guard let id else { return }
                    if reduceMotion { proxy.scrollTo(id, anchor: .center) }
                    else { withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) } }
                }
                .onChange(of: tracks.map(\.id)) { _, _ in
                    guard let selectedTrackID else { return }
                    if reduceMotion { proxy.scrollTo(selectedTrackID, anchor: .center) }
                    else { withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(selectedTrackID, anchor: .center) } }
                }
                .onAppear { if let selectedTrackID { proxy.scrollTo(selectedTrackID, anchor: .center) } }
                }
            }
        }
    }
}
