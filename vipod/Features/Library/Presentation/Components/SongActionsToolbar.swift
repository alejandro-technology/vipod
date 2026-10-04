import SwiftUI

/// Hardware-style circular action toolbar placed between the retro display and the click wheel.
public struct SongActionsToolbar: View {
    public let selectedTrack: Track?
    public let canRemove: Bool
    public let isFavorite: Bool
    public let playlists: [LibraryPlaylist]
    public let theme: iPodTheme
    public var onPlayNext: () -> Void
    public var onAddQueue: () -> Void
    public var onToggleFavorite: () -> Void
    public var onAddToPlaylist: (UUID) -> Void
    public var onRemove: () -> Void

    public init(
        selectedTrack: Track?,
        canRemove: Bool,
        isFavorite: Bool,
        playlists: [LibraryPlaylist],
        theme: iPodTheme = .classicBlack,
        onPlayNext: @escaping () -> Void,
        onAddQueue: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onAddToPlaylist: @escaping (UUID) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.selectedTrack = selectedTrack
        self.canRemove = canRemove
        self.isFavorite = isFavorite
        self.playlists = playlists
        self.theme = theme
        self.onPlayNext = onPlayNext
        self.onAddQueue = onAddQueue
        self.onToggleFavorite = onToggleFavorite
        self.onAddToPlaylist = onAddToPlaylist
        self.onRemove = onRemove
    }

    private var hasSelectedTrack: Bool {
        selectedTrack != nil
    }

    public var body: some View {
        HStack(spacing: 0) {
            Spacer()

            // 1. Play Next
            CircularActionButton(
                icon: "text.insert",
                label: String(localized: "Play Next"),
                theme: theme,
                isEnabled: hasSelectedTrack,
                accessibilityID: "track.action.playNext",
                action: onPlayNext
            )

            Spacer()

            // 2. Add to Queue
            CircularActionButton(
                icon: "text.append",
                label: String(localized: "Queue"),
                theme: theme,
                isEnabled: hasSelectedTrack,
                accessibilityID: "track.action.queueLast",
                action: onAddQueue
            )

            Spacer()

            // 3. Toggle Favorite
            CircularActionButton(
                icon: isFavorite ? "heart.fill" : "heart",
                label: String(localized: "Favorite"),
                theme: theme,
                isEnabled: hasSelectedTrack,
                accentColor: isFavorite ? Color.red : nil,
                accessibilityID: "track.action.favorite",
                action: onToggleFavorite
            )

            Spacer()

            // 4. Add to Playlist (Menu)
            playlistMenuButton

            Spacer()

            // 5. Delete (Remove from library)
            CircularActionButton(
                icon: "trash.fill",
                label: String(localized: "Delete"),
                theme: theme,
                isEnabled: canRemove,
                accentColor: canRemove ? Color.red : nil,
                accessibilityID: "library.remove",
                accessibilityLabel: selectedTrack.map {
                    String.localizedStringWithFormat(String(localized: "Remove %@"), $0.title)
                } ?? String(localized: "Remove selected song"),
                accessibilityValue: selectedTrack?.title ?? String(localized: "No song selected"),
                action: onRemove
            )

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("song.actions.toolbar")
    }

    private var playlistMenuButton: some View {
        Menu {
            if playlists.isEmpty {
                Text(String(localized: "No Playlists Available"))
            } else {
                ForEach(playlists) { playlist in
                    Button(playlist.name) {
                        onAddToPlaylist(playlist.id)
                    }
                    .accessibilityIdentifier("track.addToPlaylist.\(playlist.id.uuidString)")
                }
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(theme.palette.wheel)
                        .overlay(Circle().stroke(theme.palette.wheelEdge, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)

                    Image(systemName: "music.note.list")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(hasSelectedTrack ? theme.palette.controlText : theme.palette.secondaryText)
                }
                .frame(width: 36, height: 36)

                Text(String(localized: "Playlist"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hasSelectedTrack ? theme.palette.controlText : theme.palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 52, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(CircularActionButtonPressStyle())
        .disabled(!hasSelectedTrack)
        .opacity(hasSelectedTrack ? 1.0 : 0.35)
        .accessibilityLabel(String(localized: "Add to Playlist"))
        .accessibilityHint(String(localized: "Add selected song to a playlist"))
        .accessibilityIdentifier("track.action.playlist")
    }
}

public struct CircularActionButton: View {
    public let icon: String
    public let label: String
    public let theme: iPodTheme
    public let isEnabled: Bool
    public var accentColor: Color? = nil
    public var accessibilityID: String? = nil
    public var accessibilityLabel: String? = nil
    public var accessibilityValue: String? = nil
    public var action: () -> Void

    public init(
        icon: String,
        label: String,
        theme: iPodTheme = .classicBlack,
        isEnabled: Bool,
        accentColor: Color? = nil,
        accessibilityID: String? = nil,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.theme = theme
        self.isEnabled = isEnabled
        self.accentColor = accentColor
        self.accessibilityID = accessibilityID
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(theme.palette.wheel)
                        .overlay(Circle().stroke(theme.palette.wheelEdge, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)

                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                .frame(width: 36, height: 36)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 52, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(CircularActionButtonPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.35)
        .accessibilityLabel(accessibilityLabel ?? label)
        .accessibilityValue(accessibilityValue ?? "")
        .accessibilityIdentifier(accessibilityID ?? "")
    }

    private var iconColor: Color {
        if !isEnabled { return theme.palette.secondaryText }
        if let accent = accentColor { return accent }
        return theme.palette.controlText
    }

    private var textColor: Color {
        if !isEnabled { return theme.palette.secondaryText }
        return theme.palette.controlText
    }
}

public struct CircularActionButtonPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
