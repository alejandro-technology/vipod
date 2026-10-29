import SwiftUI

struct NowPlayingActionsToolbar: View {
    let track: Track?
    let playlists: [LibraryPlaylist]
    let canOpenQueue: Bool
    let isShuffled: Bool
    let theme: iPodTheme
    let openQueue: () -> Void
    let addToPlaylist: (UUID) -> Void
    let toggleShuffle: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Spacer(minLength: 0)
            Menu {
                ForEach(playlists) { playlist in
                    Button(playlist.name) { addToPlaylist(playlist.id) }
                        .accessibilityIdentifier("nowPlaying.playlist.\(playlist.id.uuidString)")
                }
            } label: {
                actionLabel("Playlist", icon: "music.note.list", enabled: track != nil && !playlists.isEmpty)
            }
            .disabled(track == nil || playlists.isEmpty)
            .accessibilityLabel(String(localized: "Playlist"))
            .accessibilityHint(String(localized: "Add the current song to a playlist"))
            .accessibilityIdentifier("nowPlaying.action.playlist")

            Button(action: openQueue) {
                actionLabel("Queue", icon: "text.append", enabled: canOpenQueue)
            }
            .disabled(!canOpenQueue)
            .accessibilityLabel(String(localized: "Queue"))
            .accessibilityIdentifier("nowPlaying.action.queue")

            Button(action: toggleShuffle) {
                actionLabel("Shuffle", icon: "shuffle", enabled: track != nil)
            }
            .disabled(track == nil)
            .accessibilityLabel(String(localized: "Shuffle"))
            .accessibilityValue(isShuffled ? String(localized: "On") : String(localized: "Off"))
            .accessibilityHint(String(localized: "Toggle shuffle for the playback queue"))
            .accessibilityIdentifier("nowPlaying.action.shuffle")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nowPlaying.actions.toolbar")
    }

    private func actionLabel(_ title: String, icon: String, enabled: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(enabled ? theme.palette.controlText : theme.palette.secondaryText)
        .frame(width: 54, height: 38)
        .contentShape(Rectangle())
    }
}
