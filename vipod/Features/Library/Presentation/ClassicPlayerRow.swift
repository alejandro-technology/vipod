import Foundation

public enum PlayerThemeChoice: String, Hashable, Sendable {
    case black
    case white
}

public struct ClassicPlayerRow: Identifiable, Sendable {
    public enum Action: Sendable {
        case open(PlayerDestination)
        case play(Track, queue: [Track])
        case addToPlaylist(Track, playlistID: UUID)
        case shuffle([Track])
        case importMusic
        case setTheme(PlayerThemeChoice)
        case setRepeat(RepeatMode)
        case setBluetoothKind(BluetoothDeviceKind)
        case toggleShuffle
    }

    public let id: String
    public let title: String
    public let subtitle: String?
    public let action: Action

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        action: Action
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }
}
